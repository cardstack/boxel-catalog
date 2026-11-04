/* eslint-disable */
// @ts-nocheck -- vendored minified glimmer-motion/Choreo build
// glimmer-motion + film (Reel, Lyric) + camera sampler — realm bundle (ESM, single file)
// External: @ember/*, @glimmer/*, ember-modifier (host-provided); @ember/renderer is shimmed.


// dist/beacon.js
import { modifier } from "ember-modifier";

// dist/choreo/measure.js
var rect = (r) => ({
  height: r.height,
  width: r.width,
  x: r.left,
  y: r.top
});
var minus = (a, b) => ({
  height: a.height,
  width: a.width,
  x: a.left - b.left,
  y: a.top - b.top
});
var inkBox = (el) => {
  const doc = el.ownerDocument;
  if (!doc) {
    return void 0;
  }
  const range = doc.createRange();
  range.selectNodeContents(el);
  const r = range.getBoundingClientRect();
  if (r.width < 0.5 && r.height < 0.5) {
    return void 0;
  }
  return r;
};
var substanceOf = (el) => {
  const marked = el.querySelector("[data-choreo-substance]")?.getBoundingClientRect();
  if (marked) {
    return marked;
  }
  if (el.getAttribute("data-choreo-pack") === "content") {
    return inkBox(el);
  }
  return void 0;
};
var offsetBox = (el) => (el.offsetParent ?? el.parentElement ?? el).getBoundingClientRect();
var measure = (el) => ({
  el: el.getBoundingClientRect(),
  // read with the geometry, while the element is still attached: a removed
  // skin is detached DOM by the time a crossing asks what color it wore
  paint: getComputedStyle(el).backgroundColor,
  parent: offsetBox(el),
  // Keynote matches OBJECTS, not slide frames: an element may declare its
  // visible subject with [data-choreo-substance], or pack="content" (the
  // shrink-wrap / ink, no extra node). Captured with the geometry for
  // the same reason paint is.
  substance: substanceOf(el)
});
var boundsOf = (snap, root) => ({
  context: minus(snap.el, root),
  page: rect(snap.el),
  paint: snap.paint,
  parent: minus(snap.el, snap.parent),
  substance: snap.substance && rect(snap.substance)
});
var measureBounds = (el, root) => boundsOf(measure(el), root);

// dist/choreo/beacons.js
var registry = /* @__PURE__ */ new Map();
function registerBeacon(name, element) {
  if (!registry.has(name)) {
    registry.set(name, element);
  }
  return () => {
    if (registry.get(name) === element) {
      registry.delete(name);
    }
  };
}
function measureBeacons(root) {
  const out = /* @__PURE__ */ new Map();
  for (const [name, el] of registry) {
    if (!el.isConnected) {
      continue;
    }
    out.set(name, measureBounds(el, root));
  }
  return out;
}
var isBeaconRef = (v) => typeof v === "object" && v !== null && typeof v.beacon === "string";

// dist/beacon.js
var beacon = modifier((element, positional) => {
  const name = positional[0];
  if (!name) {
    return;
  }
  return registerBeacon(name, element);
});

// dist/choreo.js
import { registerDestructor } from "@ember/destroyable";
import Component4 from "@glimmer/component";
import { tracked as tracked2 } from "@glimmer/tracking";
import { consumeTag as consumeTag2, VOLATILE_TAG as VOLATILE_TAG2 } from "@glimmer/validator";
import { modifier as modifier5 } from "ember-modifier";

// dist/activity.js
var probes = /* @__PURE__ */ new Set();
function registerBusyProbe(probe) {
  probes.add(probe);
  return () => {
    probes.delete(probe);
  };
}

// dist/choreo/changeset.js
function onstage(s) {
  const box = (s.type === "removed" ? s.initial : s.final ?? s.initial)?.page;
  if (!box) {
    return true;
  }
  return box.x < window.innerWidth && box.y < window.innerHeight && box.x + box.width > 0 && box.y + box.height > 0;
}
var isStill = (s) => !s.delta || s.delta.x === 0 && s.delta.y === 0 && s.delta.width === 0 && s.delta.height === 0;
var Changeset = class {
  inserted;
  kept;
  removed;
  /**
   * The box a `{{beacon}}` claimed this pass, or null if nothing claimed that
   * name. It is a measurement, not a sprite: a beacon is never inserted, kept
   * or removed, and a missing one is a no-op for whatever wanted to borrow it.
   *
   * Closed over rather than stored as a field, so this class stays structurally
   * identical to ChangesetLike — a property function written against the
   * concrete Changeset must still accept the interface it is handed.
   */
  beacon;
  /**
   * The camera zoom the world was measured under (§6.3). Every box in this
   * changeset is a page-space measurement taken through the region's frame
   * transform, but a step's values are written in the sprite's own local
   * space — so geometry that becomes inline pixels must be divided back by
   * this before it is animated. 1 when the frame is at rest.
   */
  measureZoom;
  /** the frame's own size in local pixels, from the same final layout */
  frame;
  /** what the page shows behind this region — see ChangesetLike.ground */
  ground;
  constructor(inserted, removed, kept, beacons = /* @__PURE__ */ new Map(), measureZoom = 1, frame2, ground) {
    this.inserted = inserted;
    this.removed = removed;
    this.kept = kept;
    this.beacon = (name) => beacons.get(name) ?? null;
    this.measureZoom = measureZoom;
    this.frame = frame2;
    this.ground = ground;
  }
  get all() {
    return [...this.kept, ...this.inserted, ...this.removed];
  }
  /** something happened this pass that a choreography could animate */
  get dirty() {
    return this.inserted.length > 0 || this.removed.length > 0 || this.kept.some((s) => !isStill(s));
  }
  sprites(query) {
    if (Array.isArray(query)) {
      const out = [];
      for (const q of query) {
        for (const s of this.sprites(q)) {
          if (!out.includes(s)) {
            out.push(s);
          }
        }
      }
      return out;
    }
    let pool;
    switch (query.type) {
      case "inserted":
        pool = this.inserted;
        break;
      case "removed":
        pool = this.removed;
        break;
      case "kept":
        pool = this.kept;
        break;
      case "still":
        pool = this.kept.filter(isStill);
        break;
      case "moved":
        pool = this.kept.filter((s) => !isStill(s));
        break;
      case "received":
        pool = this.kept.filter((s) => s.counterpart);
        break;
      case "counterpart":
        pool = this.removed.filter((s) => s.claimed);
        break;
      case "departed":
        pool = this.removed.filter((s) => !s.claimed && !s.sent);
        break;
      default:
        pool = this.all;
    }
    return pool.filter((s) => (query.id === void 0 || s.id === query.id) && (query.role === void 0 || s.role === query.role) && (!query.onstage || onstage(s)));
  }
  sprite(query) {
    const found = this.sprites(query);
    if (found.length > 1) {
      throw new Error(`choreo: more than one sprite matches ${JSON.stringify(query)}`);
    }
    return found[0] ?? null;
  }
};

// ../../node_modules/.pnpm/motion-utils@13.0.0/node_modules/motion-utils/dist/es/array.mjs
function addUniqueItem(arr, item) {
  if (arr.indexOf(item) === -1)
    arr.push(item);
}
function removeItem(arr, item) {
  const index = arr.indexOf(item);
  if (index > -1)
    arr.splice(index, 1);
}
function moveItem([...arr], fromIndex, toIndex) {
  const startIndex = fromIndex < 0 ? arr.length + fromIndex : fromIndex;
  if (startIndex >= 0 && startIndex < arr.length) {
    const endIndex = toIndex < 0 ? arr.length + toIndex : toIndex;
    const [item] = arr.splice(fromIndex, 1);
    arr.splice(endIndex, 0, item);
  }
  return arr;
}

// ../../node_modules/.pnpm/motion-utils@13.0.0/node_modules/motion-utils/dist/es/clamp.mjs
var clamp = (min, max, v) => {
  if (v > max)
    return max;
  if (v < min)
    return min;
  return v;
};

// ../../node_modules/.pnpm/motion-utils@13.0.0/node_modules/motion-utils/dist/es/format-error-message.mjs
function formatErrorMessage(message, errorCode) {
  return errorCode ? `${message}. For more information and steps for solving, visit https://motion.dev/troubleshooting/${errorCode}` : message;
}

// ../../node_modules/.pnpm/motion-utils@13.0.0/node_modules/motion-utils/dist/es/errors.mjs
var warning = () => {
};
var invariant = () => {
};
if (typeof process !== "undefined" && true) {
  warning = (check, message, errorCode) => {
    if (!check && typeof console !== "undefined") {
      console.warn(formatErrorMessage(message, errorCode));
    }
  };
  invariant = (check, message, errorCode) => {
    if (!check) {
      throw new Error(formatErrorMessage(message, errorCode));
    }
  };
}

// ../../node_modules/.pnpm/motion-utils@13.0.0/node_modules/motion-utils/dist/es/global-config.mjs
var MotionGlobalConfig = {};

// ../../node_modules/.pnpm/motion-utils@13.0.0/node_modules/motion-utils/dist/es/is-numerical-string.mjs
var isNumericalString = (v) => /^-?(?:\d+(?:\.\d+)?|\.\d+)$/u.test(v);

// ../../node_modules/.pnpm/motion-utils@13.0.0/node_modules/motion-utils/dist/es/is-object.mjs
var isObject = (value) => typeof value === "object" && value !== null;

// ../../node_modules/.pnpm/motion-utils@13.0.0/node_modules/motion-utils/dist/es/is-zero-value-string.mjs
var isZeroValueString = (v) => /^0[^.\s]+$/u.test(v);

// ../../node_modules/.pnpm/motion-utils@13.0.0/node_modules/motion-utils/dist/es/memo.mjs
// @__NO_SIDE_EFFECTS__
function memo(callback) {
  let result;
  return () => {
    if (result === void 0)
      result = callback();
    return result;
  };
}

// ../../node_modules/.pnpm/motion-utils@13.0.0/node_modules/motion-utils/dist/es/noop.mjs
var noop = /* @__NO_SIDE_EFFECTS__ */ (any) => any;

// ../../node_modules/.pnpm/motion-utils@13.0.0/node_modules/motion-utils/dist/es/pipe.mjs
var pipe = (...transformers) => transformers.reduce((a, b) => (v) => b(a(v)));

// ../../node_modules/.pnpm/motion-utils@13.0.0/node_modules/motion-utils/dist/es/progress.mjs
var progress = /* @__NO_SIDE_EFFECTS__ */ (from, to2, value) => {
  const range = to2 - from;
  return range ? (value - from) / range : 1;
};

// ../../node_modules/.pnpm/motion-utils@13.0.0/node_modules/motion-utils/dist/es/subscription-manager.mjs
var SubscriptionManager = class {
  constructor() {
    this.subscriptions = [];
  }
  add(handler) {
    addUniqueItem(this.subscriptions, handler);
    return () => removeItem(this.subscriptions, handler);
  }
  notify(a, b, c) {
    const numSubscriptions = this.subscriptions.length;
    if (!numSubscriptions)
      return;
    if (numSubscriptions === 1) {
      this.subscriptions[0](a, b, c);
    } else {
      for (let i = 0; i < numSubscriptions; i++) {
        const handler = this.subscriptions[i];
        handler && handler(a, b, c);
      }
    }
  }
  getSize() {
    return this.subscriptions.length;
  }
  clear() {
    this.subscriptions.length = 0;
  }
};

// ../../node_modules/.pnpm/motion-utils@13.0.0/node_modules/motion-utils/dist/es/time-conversion.mjs
var secondsToMilliseconds = /* @__NO_SIDE_EFFECTS__ */ (seconds) => seconds * 1e3;
var millisecondsToSeconds = /* @__NO_SIDE_EFFECTS__ */ (milliseconds) => milliseconds / 1e3;

// ../../node_modules/.pnpm/motion-utils@13.0.0/node_modules/motion-utils/dist/es/velocity-per-second.mjs
var velocityPerSecond = /* @__NO_SIDE_EFFECTS__ */ (velocity, frameDuration) => frameDuration ? velocity * (1e3 / frameDuration) : 0;

// ../../node_modules/.pnpm/motion-utils@13.0.0/node_modules/motion-utils/dist/es/warn-once.mjs
var warned = /* @__PURE__ */ new Set();
function warnOnce(condition, message, errorCode) {
  if (condition || warned.has(message))
    return;
  console.warn(formatErrorMessage(message, errorCode));
  warned.add(message);
}

// ../../node_modules/.pnpm/motion-utils@13.0.0/node_modules/motion-utils/dist/es/easing/cubic-bezier.mjs
var calcBezier = (t, a1, a2) => (((1 - 3 * a2 + 3 * a1) * t + (3 * a2 - 6 * a1)) * t + 3 * a1) * t;
var subdivisionPrecision = 1e-7;
var subdivisionMaxIterations = 12;
function binarySubdivide(x, lowerBound, upperBound, mX1, mX2) {
  let currentX;
  let currentT;
  let i = 0;
  do {
    currentT = lowerBound + (upperBound - lowerBound) / 2;
    currentX = calcBezier(currentT, mX1, mX2) - x;
    if (currentX > 0) {
      upperBound = currentT;
    } else {
      lowerBound = currentT;
    }
  } while (Math.abs(currentX) > subdivisionPrecision && ++i < subdivisionMaxIterations);
  return currentT;
}
// @__NO_SIDE_EFFECTS__
function cubicBezier(mX1, mY1, mX2, mY2) {
  if (mX1 === mY1 && mX2 === mY2)
    return noop;
  const getTForX = (aX) => binarySubdivide(aX, 0, 1, mX1, mX2);
  return (t) => t === 0 || t === 1 ? t : calcBezier(getTForX(t), mY1, mY2);
}

// ../../node_modules/.pnpm/motion-utils@13.0.0/node_modules/motion-utils/dist/es/easing/modifiers/mirror.mjs
var mirrorEasing = /* @__NO_SIDE_EFFECTS__ */ (easing) => (p) => p <= 0.5 ? easing(2 * p) / 2 : (2 - easing(2 * (1 - p))) / 2;

// ../../node_modules/.pnpm/motion-utils@13.0.0/node_modules/motion-utils/dist/es/easing/modifiers/reverse.mjs
var reverseEasing = /* @__NO_SIDE_EFFECTS__ */ (easing) => (p) => 1 - easing(1 - p);

// ../../node_modules/.pnpm/motion-utils@13.0.0/node_modules/motion-utils/dist/es/easing/back.mjs
var backOut = /* @__PURE__ */ cubicBezier(0.33, 1.53, 0.69, 0.99);
var backIn = /* @__PURE__ */ reverseEasing(backOut);
var backInOut = /* @__PURE__ */ mirrorEasing(backIn);

// ../../node_modules/.pnpm/motion-utils@13.0.0/node_modules/motion-utils/dist/es/easing/anticipate.mjs
var anticipate = (p) => p >= 1 ? 1 : (p *= 2) < 1 ? 0.5 * backIn(p) : 0.5 * (2 - Math.pow(2, -10 * (p - 1)));

// ../../node_modules/.pnpm/motion-utils@13.0.0/node_modules/motion-utils/dist/es/easing/circ.mjs
var circIn = (p) => 1 - Math.sin(Math.acos(p));
var circOut = reverseEasing(circIn);
var circInOut = mirrorEasing(circIn);

// ../../node_modules/.pnpm/motion-utils@13.0.0/node_modules/motion-utils/dist/es/easing/ease.mjs
var easeIn = /* @__PURE__ */ cubicBezier(0.42, 0, 1, 1);
var easeOut = /* @__PURE__ */ cubicBezier(0, 0, 0.58, 1);
var easeInOut = /* @__PURE__ */ cubicBezier(0.42, 0, 0.58, 1);

// ../../node_modules/.pnpm/motion-utils@13.0.0/node_modules/motion-utils/dist/es/easing/utils/is-easing-array.mjs
var isEasingArray = /* @__NO_SIDE_EFFECTS__ */ (ease3) => {
  return Array.isArray(ease3) && typeof ease3[0] !== "number";
};

// ../../node_modules/.pnpm/motion-utils@13.0.0/node_modules/motion-utils/dist/es/easing/utils/is-bezier-definition.mjs
var isBezierDefinition = /* @__NO_SIDE_EFFECTS__ */ (easing) => Array.isArray(easing) && typeof easing[0] === "number";

// ../../node_modules/.pnpm/motion-utils@13.0.0/node_modules/motion-utils/dist/es/easing/utils/map.mjs
var easingLookup = {
  linear: noop,
  easeIn,
  easeInOut,
  easeOut,
  circIn,
  circInOut,
  circOut,
  backIn,
  backInOut,
  backOut,
  anticipate
};
var isValidEasing = (easing) => {
  return typeof easing === "string";
};
var easingDefinitionToFunction = (definition) => {
  if (isBezierDefinition(definition)) {
    invariant(definition.length === 4, `Cubic bezier arrays must contain four numerical values.`, "cubic-bezier-length");
    const [x1, y1, x2, y2] = definition;
    return cubicBezier(x1, y1, x2, y2);
  } else if (isValidEasing(definition)) {
    invariant(easingLookup[definition] !== void 0, `Invalid easing type '${definition}'`, "invalid-easing-type");
    return easingLookup[definition];
  }
  return definition;
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/frameloop/order.mjs
var stepsOrder = [
  "setup",
  // Compute
  "read",
  // Read
  "resolveKeyframes",
  // Write/Read/Write/Read
  "preUpdate",
  // Compute
  "update",
  // Compute
  "preRender",
  // Compute
  "render",
  // Write
  "postRender"
  // Compute
];

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/frameloop/render-step.mjs
function createRenderStep(runNextFrame) {
  let thisFrame = /* @__PURE__ */ new Set();
  let nextFrame = /* @__PURE__ */ new Set();
  let isProcessing = false;
  let flushNextFrame = false;
  const toKeepAlive = /* @__PURE__ */ new WeakSet();
  let latestFrameData = {
    delta: 0,
    timestamp: 0,
    isProcessing: false
  };
  function triggerCallback(callback) {
    if (toKeepAlive.has(callback)) {
      step.schedule(callback);
      runNextFrame();
    }
    callback(latestFrameData);
  }
  const step = {
    /**
     * Schedule a process to run on the next frame.
     */
    schedule: (callback, keepAlive = false, immediate = false) => {
      const addToCurrentFrame = immediate && isProcessing;
      const queue = addToCurrentFrame ? thisFrame : nextFrame;
      if (keepAlive)
        toKeepAlive.add(callback);
      queue.add(callback);
      return callback;
    },
    /**
     * Cancel the provided callback from running on the next frame.
     */
    cancel: (callback) => {
      nextFrame.delete(callback);
      toKeepAlive.delete(callback);
    },
    /**
     * Execute all schedule callbacks.
     */
    process: (frameData2) => {
      latestFrameData = frameData2;
      if (isProcessing) {
        flushNextFrame = true;
        return;
      }
      isProcessing = true;
      const prevFrame = thisFrame;
      thisFrame = nextFrame;
      nextFrame = prevFrame;
      thisFrame.forEach(triggerCallback);
      thisFrame.clear();
      isProcessing = false;
      if (flushNextFrame) {
        flushNextFrame = false;
        step.process(frameData2);
      }
    }
  };
  return step;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/frameloop/batcher.mjs
var maxElapsed = 40;
function createRenderBatcher(scheduleNextBatch, allowKeepAlive) {
  let runNextFrame = false;
  let useDefaultElapsed = true;
  const state = {
    delta: 0,
    timestamp: 0,
    isProcessing: false
  };
  const flagRunNextFrame = () => runNextFrame = true;
  const steps = stepsOrder.reduce((acc, key) => {
    acc[key] = createRenderStep(flagRunNextFrame);
    return acc;
  }, {});
  const { setup, read, resolveKeyframes, preUpdate, update, preRender, render, postRender: postRender2 } = steps;
  const processBatch = () => {
    const useManualTiming = MotionGlobalConfig.useManualTiming;
    const timestamp = useManualTiming ? state.timestamp : performance.now();
    runNextFrame = false;
    if (!useManualTiming) {
      state.delta = useDefaultElapsed ? 1e3 / 60 : Math.max(Math.min(timestamp - state.timestamp, maxElapsed), 1);
    }
    state.timestamp = timestamp;
    state.isProcessing = true;
    setup.process(state);
    read.process(state);
    resolveKeyframes.process(state);
    preUpdate.process(state);
    update.process(state);
    preRender.process(state);
    render.process(state);
    postRender2.process(state);
    state.isProcessing = false;
    if (runNextFrame && allowKeepAlive) {
      useDefaultElapsed = false;
      scheduleNextBatch(processBatch);
    }
  };
  const wake = () => {
    runNextFrame = true;
    useDefaultElapsed = true;
    if (!state.isProcessing) {
      scheduleNextBatch(processBatch);
    }
  };
  const schedule6 = stepsOrder.reduce((acc, key) => {
    const step = steps[key];
    acc[key] = (process2, keepAlive = false, immediate = false) => {
      if (!runNextFrame)
        wake();
      return step.schedule(process2, keepAlive, immediate);
    };
    return acc;
  }, {});
  const cancel = (process2) => {
    for (let i = 0; i < stepsOrder.length; i++) {
      steps[stepsOrder[i]].cancel(process2);
    }
  };
  return { schedule: schedule6, cancel, state, steps };
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/frameloop/frame.mjs
var { schedule: frame, cancel: cancelFrame, state: frameData, steps: frameSteps } = /* @__PURE__ */ createRenderBatcher(typeof requestAnimationFrame !== "undefined" ? requestAnimationFrame : noop, true);

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/frameloop/sync-time.mjs
var now;
function clearTime() {
  now = void 0;
}
var time = {
  now: () => {
    if (now === void 0) {
      time.set(frameData.isProcessing || MotionGlobalConfig.useManualTiming ? frameData.timestamp : performance.now());
    }
    return now;
  },
  set: (newTime) => {
    now = newTime;
    queueMicrotask(clearTime);
  }
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/utils/is-css-variable.mjs
var checkStringStartsWith = (token) => (key) => typeof key === "string" && key.startsWith(token);
var isCSSVariableName = /* @__PURE__ */ checkStringStartsWith("--");
var startsAsVariableToken = /* @__PURE__ */ checkStringStartsWith("var(--");
var isCSSVariableToken = (value) => {
  const startsWithToken = startsAsVariableToken(value);
  if (!startsWithToken)
    return false;
  return singleCssVariableRegex.test(value.split("/*")[0].trim());
};
var singleCssVariableRegex = /var\(--(?:[\w-]+\s*|[\w-]+\s*,(?:\s*[^)(\s]|\s*\((?:[^)(]|\([^)(]*\))*\))+\s*)\)$/iu;
function containsCSSVariable(value) {
  if (typeof value !== "string")
    return false;
  return value.split("/*")[0].includes("var(--");
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/types/numbers/index.mjs
var number = {
  test: (v) => typeof v === "number",
  parse: parseFloat,
  transform: (v) => v
};
var alpha = {
  ...number,
  transform: (v) => clamp(0, 1, v)
};
var scale = {
  ...number,
  default: 1
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/types/utils/sanitize.mjs
var sanitize = (v) => Math.round(v * 1e5) / 1e5;

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/types/utils/float-regex.mjs
var floatRegex = /-?(?:\d+(?:\.\d+)?|\.\d+)/gu;

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/types/utils/is-nullish.mjs
function isNullish(v) {
  return v == null;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/types/utils/single-color-regex.mjs
var singleColorRegex = /^(?:#[\da-f]{3,8}|(?:rgb|hsl)a?\((?:-?[\d.]+%?[,\s]+){2}-?[\d.]+%?\s*(?:[,/]\s*)?(?:\b\d+(?:\.\d+)?|\.\d+)?%?\))$/iu;

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/types/color/utils.mjs
var isColorString = (type, testProp) => (v) => {
  return Boolean(typeof v === "string" && singleColorRegex.test(v) && v.startsWith(type) || testProp && !isNullish(v) && Object.prototype.hasOwnProperty.call(v, testProp));
};
var splitColor = (aName, bName, cName) => (v) => {
  if (typeof v !== "string")
    return v;
  const [a, b, c, alpha2] = v.match(floatRegex);
  return {
    [aName]: parseFloat(a),
    [bName]: parseFloat(b),
    [cName]: parseFloat(c),
    alpha: alpha2 !== void 0 ? parseFloat(alpha2) : 1
  };
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/types/color/rgba.mjs
var clampRgbUnit = (v) => clamp(0, 255, v);
var rgbUnit = {
  ...number,
  transform: (v) => Math.round(clampRgbUnit(v))
};
var rgba = {
  test: /* @__PURE__ */ isColorString("rgb", "red"),
  parse: /* @__PURE__ */ splitColor("red", "green", "blue"),
  transform: ({ red, green, blue, alpha: alpha$1 = 1 }) => "rgba(" + rgbUnit.transform(red) + ", " + rgbUnit.transform(green) + ", " + rgbUnit.transform(blue) + ", " + sanitize(alpha.transform(alpha$1)) + ")"
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/types/color/hex.mjs
function parseHex(v) {
  let r = "";
  let g = "";
  let b = "";
  let a = "";
  if (v.length > 5) {
    r = v.substring(1, 3);
    g = v.substring(3, 5);
    b = v.substring(5, 7);
    a = v.substring(7, 9);
  } else {
    r = v.substring(1, 2);
    g = v.substring(2, 3);
    b = v.substring(3, 4);
    a = v.substring(4, 5);
    r += r;
    g += g;
    b += b;
    a += a;
  }
  return {
    red: parseInt(r, 16),
    green: parseInt(g, 16),
    blue: parseInt(b, 16),
    alpha: a ? parseInt(a, 16) / 255 : 1
  };
}
var hex = {
  test: /* @__PURE__ */ isColorString("#"),
  parse: parseHex,
  transform: rgba.transform
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/types/numbers/units.mjs
var createUnitType = /* @__NO_SIDE_EFFECTS__ */ (unit) => ({
  test: (v) => typeof v === "string" && v.endsWith(unit) && v.split(" ").length === 1,
  parse: parseFloat,
  transform: (v) => `${v}${unit}`
});
var degrees = /* @__PURE__ */ createUnitType("deg");
var percent = /* @__PURE__ */ createUnitType("%");
var px = /* @__PURE__ */ createUnitType("px");
var vh = /* @__PURE__ */ createUnitType("vh");
var vw = /* @__PURE__ */ createUnitType("vw");
var progressPercentage = /* @__PURE__ */ (() => ({
  ...percent,
  parse: (v) => percent.parse(v) / 100,
  transform: (v) => percent.transform(v * 100)
}))();

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/types/color/hsla.mjs
var hsla = {
  test: /* @__PURE__ */ isColorString("hsl", "hue"),
  parse: /* @__PURE__ */ splitColor("hue", "saturation", "lightness"),
  transform: ({ hue, saturation, lightness, alpha: alpha$1 = 1 }) => {
    return "hsla(" + Math.round(hue) + ", " + percent.transform(sanitize(saturation)) + ", " + percent.transform(sanitize(lightness)) + ", " + sanitize(alpha.transform(alpha$1)) + ")";
  }
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/types/color/index.mjs
var color = {
  test: (v) => rgba.test(v) || hex.test(v) || hsla.test(v),
  parse: (v) => {
    if (rgba.test(v)) {
      return rgba.parse(v);
    } else if (hsla.test(v)) {
      return hsla.parse(v);
    } else {
      return hex.parse(v);
    }
  },
  transform: (v) => {
    return typeof v === "string" ? v : v.hasOwnProperty("red") ? rgba.transform(v) : hsla.transform(v);
  },
  getAnimatableNone: (v) => {
    const parsed = color.parse(v);
    parsed.alpha = 0;
    return color.transform(parsed);
  }
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/types/utils/color-regex.mjs
var colorRegex = /(?:#[\da-f]{3,8}|(?:rgb|hsl)a?\((?:-?[\d.]+%?[,\s]+){2}-?[\d.]+%?\s*(?:[,/]\s*)?(?:\b\d+(?:\.\d+)?|\.\d+)?%?\))/giu;

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/types/complex/index.mjs
function test(v) {
  return isNaN(v) && typeof v === "string" && (v.match(floatRegex)?.length || 0) + (v.match(colorRegex)?.length || 0) > 0;
}
var NUMBER_TOKEN = "number";
var COLOR_TOKEN = "color";
var VAR_TOKEN = "var";
var VAR_FUNCTION_TOKEN = "var(";
var SPLIT_TOKEN = "${}";
var complexRegex = /var\s*\(\s*--(?:[\w-]+\s*|[\w-]+\s*,(?:\s*[^)(\s]|\s*\((?:[^)(]|\([^)(]*\))*\))+\s*)\)|#[\da-f]{3,8}|(?:rgb|hsl)a?\((?:-?[\d.]+%?[,\s]+){2}-?[\d.]+%?\s*(?:[,/]\s*)?(?:\b\d+(?:\.\d+)?|\.\d+)?%?\)|-?(?:\d+(?:\.\d+)?|\.\d+)/giu;
function analyseComplexValue(value) {
  const originalValue = value.toString();
  const values = [];
  const indexes = {
    color: [],
    number: [],
    var: []
  };
  const types = [];
  let i = 0;
  const tokenised = originalValue.replace(complexRegex, (parsedValue) => {
    if (color.test(parsedValue)) {
      indexes.color.push(i);
      types.push(COLOR_TOKEN);
      values.push(color.parse(parsedValue));
    } else if (parsedValue.startsWith(VAR_FUNCTION_TOKEN)) {
      indexes.var.push(i);
      types.push(VAR_TOKEN);
      values.push(parsedValue);
    } else {
      indexes.number.push(i);
      types.push(NUMBER_TOKEN);
      values.push(parseFloat(parsedValue));
    }
    ++i;
    return SPLIT_TOKEN;
  });
  const split2 = tokenised.split(SPLIT_TOKEN);
  return { values, split: split2, indexes, types };
}
function parseComplexValue(v) {
  return analyseComplexValue(v).values;
}
function buildTransformer({ split: split2, types }) {
  const numSections = split2.length;
  return (v) => {
    let output = "";
    for (let i = 0; i < numSections; i++) {
      output += split2[i];
      if (v[i] !== void 0) {
        const type = types[i];
        if (type === NUMBER_TOKEN) {
          output += sanitize(v[i]);
        } else if (type === COLOR_TOKEN) {
          output += color.transform(v[i]);
        } else {
          output += v[i];
        }
      }
    }
    return output;
  };
}
function createTransformer(source) {
  return buildTransformer(analyseComplexValue(source));
}
var convertNumbersToZero = (v) => typeof v === "number" ? 0 : color.test(v) ? color.getAnimatableNone(v) : v;
var convertToZero = (value, splitBefore) => {
  if (typeof value === "number") {
    return splitBefore?.trim().endsWith("/") ? value : 0;
  }
  return convertNumbersToZero(value);
};
function getAnimatableNone(v) {
  const info = analyseComplexValue(v);
  const transformer = buildTransformer(info);
  return transformer(info.values.map((value, i) => convertToZero(value, info.split[i])));
}
var complex = {
  test,
  parse: parseComplexValue,
  createTransformer,
  getAnimatableNone
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/types/color/hsla-to-rgba.mjs
function hueToRgb(p, q, t) {
  if (t < 0)
    t += 1;
  if (t > 1)
    t -= 1;
  if (t < 1 / 6)
    return p + (q - p) * 6 * t;
  if (t < 1 / 2)
    return q;
  if (t < 2 / 3)
    return p + (q - p) * (2 / 3 - t) * 6;
  return p;
}
function hslaToRgba({ hue, saturation, lightness, alpha: alpha2 }) {
  hue /= 360;
  saturation /= 100;
  lightness /= 100;
  let red = 0;
  let green = 0;
  let blue = 0;
  if (!saturation) {
    red = green = blue = lightness;
  } else {
    const q = lightness < 0.5 ? lightness * (1 + saturation) : lightness + saturation - lightness * saturation;
    const p = 2 * lightness - q;
    red = hueToRgb(p, q, hue + 1 / 3);
    green = hueToRgb(p, q, hue);
    blue = hueToRgb(p, q, hue - 1 / 3);
  }
  return {
    red: Math.round(red * 255),
    green: Math.round(green * 255),
    blue: Math.round(blue * 255),
    alpha: alpha2
  };
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/utils/mix/immediate.mjs
function mixImmediate(a, b) {
  return (p) => p > 0 ? b : a;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/utils/mix/number.mjs
var mixNumber = (from, to2, progress2) => {
  return from + (to2 - from) * progress2;
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/utils/mix/color.mjs
var mixLinearColor = (from, to2, v) => {
  const fromExpo = from * from;
  const expo = v * (to2 * to2 - fromExpo) + fromExpo;
  return expo < 0 ? 0 : Math.sqrt(expo);
};
var colorTypes = [hex, rgba, hsla];
var getColorType = (v) => colorTypes.find((type) => type.test(v));
function asRGBA(color2) {
  const type = getColorType(color2);
  warning(Boolean(type), `'${color2}' is not an animatable color. Use the equivalent color code instead.`, "color-not-animatable");
  if (!Boolean(type))
    return false;
  let model = type.parse(color2);
  if (type === hsla) {
    model = hslaToRgba(model);
  }
  return model;
}
var mixColor = (from, to2) => {
  const fromRGBA = asRGBA(from);
  const toRGBA = asRGBA(to2);
  if (!fromRGBA || !toRGBA) {
    return mixImmediate(from, to2);
  }
  const blended = { ...fromRGBA };
  return (v) => {
    blended.red = mixLinearColor(fromRGBA.red, toRGBA.red, v);
    blended.green = mixLinearColor(fromRGBA.green, toRGBA.green, v);
    blended.blue = mixLinearColor(fromRGBA.blue, toRGBA.blue, v);
    blended.alpha = mixNumber(fromRGBA.alpha, toRGBA.alpha, v);
    return rgba.transform(blended);
  };
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/utils/mix/visibility.mjs
var invisibleValues = /* @__PURE__ */ new Set(["none", "hidden"]);
function mixVisibility(origin, target) {
  if (invisibleValues.has(origin)) {
    return (p) => p <= 0 ? origin : target;
  } else {
    return (p) => p >= 1 ? target : origin;
  }
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/utils/mix/complex.mjs
function mixNumber2(a, b) {
  return (p) => mixNumber(a, b, p);
}
function getMixer(a) {
  if (typeof a === "number") {
    return mixNumber2;
  } else if (typeof a === "string") {
    return isCSSVariableToken(a) ? mixImmediate : color.test(a) ? mixColor : mixComplex;
  } else if (Array.isArray(a)) {
    return mixArray;
  } else if (typeof a === "object") {
    return color.test(a) ? mixColor : mixObject;
  }
  return mixImmediate;
}
function mixArray(a, b) {
  const output = [...a];
  const numValues = output.length;
  const blendValue = a.map((v, i) => getMixer(v)(v, b[i]));
  return (p) => {
    for (let i = 0; i < numValues; i++) {
      output[i] = blendValue[i](p);
    }
    return output;
  };
}
function mixObject(a, b) {
  const output = { ...a, ...b };
  const blendValue = {};
  for (const key in output) {
    if (a[key] !== void 0 && b[key] !== void 0) {
      blendValue[key] = getMixer(a[key])(a[key], b[key]);
    }
  }
  return (v) => {
    for (const key in blendValue) {
      output[key] = blendValue[key](v);
    }
    return output;
  };
}
function matchOrder(origin, target) {
  const orderedOrigin = [];
  const pointers = { color: 0, var: 0, number: 0 };
  for (let i = 0; i < target.values.length; i++) {
    const type = target.types[i];
    const originIndex = origin.indexes[type][pointers[type]];
    const originValue = origin.values[originIndex] ?? 0;
    orderedOrigin[i] = originValue;
    pointers[type]++;
  }
  return orderedOrigin;
}
var mixComplex = (origin, target) => {
  const template = complex.createTransformer(target);
  const originStats = analyseComplexValue(origin);
  const targetStats = analyseComplexValue(target);
  const canInterpolate = originStats.indexes.var.length === targetStats.indexes.var.length && originStats.indexes.color.length === targetStats.indexes.color.length && originStats.indexes.number.length >= targetStats.indexes.number.length;
  if (canInterpolate) {
    if (invisibleValues.has(origin) && !targetStats.values.length || invisibleValues.has(target) && !originStats.values.length) {
      return mixVisibility(origin, target);
    }
    return pipe(mixArray(matchOrder(originStats, targetStats), targetStats.values), template);
  } else {
    warning(true, `Complex values '${origin}' and '${target}' too different to mix. Ensure all colors are of the same type, and that each contains the same quantity of number and color values. Falling back to instant transition.`, "complex-values-different");
    return mixImmediate(origin, target);
  }
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/utils/mix/index.mjs
function mix(from, to2, p) {
  if (typeof from === "number" && typeof to2 === "number" && typeof p === "number") {
    return mixNumber(from, to2, p);
  }
  const mixer = getMixer(from);
  return mixer(from, to2);
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/drivers/frame.mjs
var frameloopDriver = (update) => {
  const passTimestamp = ({ timestamp }) => update(timestamp);
  return {
    start: (keepAlive = true) => frame.update(passTimestamp, keepAlive),
    stop: () => cancelFrame(passTimestamp),
    /**
     * If we're processing this frame we can use the
     * framelocked timestamp to keep things in sync.
     */
    now: () => frameData.isProcessing ? frameData.timestamp : time.now()
  };
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/waapi/utils/linear.mjs
var generateLinearEasing = (easing, duration, resolution = 10) => {
  let points = "";
  const numPoints = Math.max(Math.round(duration / resolution), 2);
  for (let i = 0; i < numPoints; i++) {
    points += Math.round(easing(i / (numPoints - 1)) * 1e4) / 1e4 + ", ";
  }
  return `linear(${points.substring(0, points.length - 2)})`;
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/generators/utils/calc-duration.mjs
var maxGeneratorDuration = 2e4;
function calcGeneratorDuration(generator) {
  let duration = 0;
  const timeStep = 50;
  let state = generator.next(duration);
  while (!state.done && duration < maxGeneratorDuration) {
    duration += timeStep;
    state = generator.next(duration);
  }
  return duration >= maxGeneratorDuration ? Infinity : duration;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/generators/utils/create-generator-easing.mjs
function createGeneratorEasing(options, scale2 = 100, createGenerator) {
  const generator = createGenerator({ ...options, keyframes: [0, scale2] });
  const duration = Math.min(calcGeneratorDuration(generator), maxGeneratorDuration);
  return {
    type: "keyframes",
    ease: (progress2) => {
      return generator.next(duration * progress2).value / scale2;
    },
    duration: millisecondsToSeconds(duration)
  };
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/generators/spring.mjs
var springDefaults = {
  // Default spring physics
  stiffness: 100,
  damping: 10,
  mass: 1,
  velocity: 0,
  // Default duration/bounce-based options
  duration: 800,
  // in ms
  bounce: 0.3,
  visualDuration: 0.3,
  // in seconds
  // Rest thresholds
  restSpeed: {
    granular: 0.01,
    default: 2
  },
  restDelta: {
    granular: 5e-3,
    default: 0.5
  },
  // Limits
  minDuration: 0.01,
  // in seconds
  maxDuration: 10,
  // in seconds
  minDamping: 0.05,
  maxDamping: 1
};
function calcAngularFreq(undampedFreq, dampingRatio) {
  return undampedFreq * Math.sqrt(1 - dampingRatio * dampingRatio);
}
var rootIterations = 12;
function approximateRoot(envelope, derivative, initialGuess) {
  let result = initialGuess;
  for (let i = 1; i < rootIterations; i++) {
    result = result - envelope(result) / derivative(result);
  }
  return result;
}
var safeMin = 1e-3;
function findSpring({ duration = springDefaults.duration, bounce = springDefaults.bounce, velocity = springDefaults.velocity, mass = springDefaults.mass }) {
  let envelope;
  let derivative;
  warning(duration <= secondsToMilliseconds(springDefaults.maxDuration), "Spring duration must be 10 seconds or less", "spring-duration-limit");
  let dampingRatio = 1 - bounce;
  dampingRatio = clamp(springDefaults.minDamping, springDefaults.maxDamping, dampingRatio);
  duration = clamp(springDefaults.minDuration, springDefaults.maxDuration, millisecondsToSeconds(duration));
  if (dampingRatio < 1) {
    envelope = (undampedFreq2) => {
      const exponentialDecay = undampedFreq2 * dampingRatio;
      const delta = exponentialDecay * duration;
      const a = exponentialDecay - velocity;
      const b = calcAngularFreq(undampedFreq2, dampingRatio);
      const c = Math.exp(-delta);
      return safeMin - a / b * c;
    };
    derivative = (undampedFreq2) => {
      const exponentialDecay = undampedFreq2 * dampingRatio;
      const delta = exponentialDecay * duration;
      const d = delta * velocity + velocity;
      const e = Math.pow(dampingRatio, 2) * Math.pow(undampedFreq2, 2) * duration;
      const f = Math.exp(-delta);
      const g = calcAngularFreq(Math.pow(undampedFreq2, 2), dampingRatio);
      const factor = -envelope(undampedFreq2) + safeMin > 0 ? -1 : 1;
      return factor * ((d - e) * f) / g;
    };
  } else {
    envelope = (undampedFreq2) => {
      const a = Math.exp(-undampedFreq2 * duration);
      const b = (undampedFreq2 - velocity) * duration + 1;
      return -safeMin + a * b;
    };
    derivative = (undampedFreq2) => {
      const a = Math.exp(-undampedFreq2 * duration);
      const b = (velocity - undampedFreq2) * (duration * duration);
      return a * b;
    };
  }
  const initialGuess = 5 / duration;
  const undampedFreq = approximateRoot(envelope, derivative, initialGuess);
  duration = secondsToMilliseconds(duration);
  if (isNaN(undampedFreq)) {
    return {
      stiffness: springDefaults.stiffness,
      damping: springDefaults.damping,
      duration
    };
  } else {
    const stiffness = Math.pow(undampedFreq, 2) * mass;
    return {
      stiffness,
      damping: dampingRatio * 2 * Math.sqrt(mass * stiffness),
      duration
    };
  }
}
var durationKeys = ["duration", "bounce"];
var physicsKeys = ["stiffness", "damping", "mass"];
function isSpringType(options, keys2) {
  return keys2.some((key) => options[key] !== void 0);
}
function getSpringOptions(options) {
  let springOptions = {
    velocity: springDefaults.velocity,
    stiffness: springDefaults.stiffness,
    damping: springDefaults.damping,
    mass: springDefaults.mass,
    isResolvedFromDuration: false,
    ...options
  };
  if (!isSpringType(options, physicsKeys) && isSpringType(options, durationKeys)) {
    springOptions.velocity = 0;
    if (options.visualDuration) {
      const visualDuration = options.visualDuration;
      const root = 2 * Math.PI / (visualDuration * 1.2);
      const stiffness = root * root;
      const damping = 2 * clamp(0.05, 1, 1 - (options.bounce || 0)) * Math.sqrt(stiffness);
      springOptions = {
        ...springOptions,
        mass: springDefaults.mass,
        stiffness,
        damping
      };
    } else {
      const derived = findSpring({ ...options, velocity: 0 });
      springOptions = {
        ...springOptions,
        ...derived,
        mass: springDefaults.mass
      };
      springOptions.isResolvedFromDuration = true;
    }
  }
  return springOptions;
}
function spring(optionsOrVisualDuration = springDefaults.visualDuration, bounce = springDefaults.bounce) {
  const options = typeof optionsOrVisualDuration !== "object" ? {
    visualDuration: optionsOrVisualDuration,
    keyframes: [0, 1],
    bounce
  } : optionsOrVisualDuration;
  let { restSpeed, restDelta } = options;
  const origin = options.keyframes[0];
  const target = options.keyframes[options.keyframes.length - 1];
  const state = { done: false, value: origin };
  const { stiffness, damping, mass, duration, velocity, isResolvedFromDuration } = getSpringOptions({
    ...options,
    velocity: -millisecondsToSeconds(options.velocity || 0)
  });
  const initialVelocity = velocity || 0;
  const dampingRatio = damping / (2 * Math.sqrt(stiffness * mass));
  const initialDelta = target - origin;
  const undampedAngularFreq = millisecondsToSeconds(Math.sqrt(stiffness / mass));
  const isGranularScale = Math.abs(initialDelta) < 5;
  restSpeed || (restSpeed = isGranularScale ? springDefaults.restSpeed.granular : springDefaults.restSpeed.default);
  restDelta || (restDelta = isGranularScale ? springDefaults.restDelta.granular : springDefaults.restDelta.default);
  let resolveSpring;
  let resolveVelocity;
  let angularFreq;
  let A;
  let sinCoeff;
  let cosCoeff;
  if (dampingRatio < 1) {
    angularFreq = calcAngularFreq(undampedAngularFreq, dampingRatio);
    A = (initialVelocity + dampingRatio * undampedAngularFreq * initialDelta) / angularFreq;
    resolveSpring = (t) => {
      const envelope = Math.exp(-dampingRatio * undampedAngularFreq * t);
      return target - envelope * (A * Math.sin(angularFreq * t) + initialDelta * Math.cos(angularFreq * t));
    };
    sinCoeff = dampingRatio * undampedAngularFreq * A + initialDelta * angularFreq;
    cosCoeff = dampingRatio * undampedAngularFreq * initialDelta - A * angularFreq;
    resolveVelocity = (t) => {
      const envelope = Math.exp(-dampingRatio * undampedAngularFreq * t);
      return envelope * (sinCoeff * Math.sin(angularFreq * t) + cosCoeff * Math.cos(angularFreq * t));
    };
  } else if (dampingRatio === 1) {
    resolveSpring = (t) => target - Math.exp(-undampedAngularFreq * t) * (initialDelta + (initialVelocity + undampedAngularFreq * initialDelta) * t);
    const C = initialVelocity + undampedAngularFreq * initialDelta;
    resolveVelocity = (t) => Math.exp(-undampedAngularFreq * t) * (undampedAngularFreq * C * t - initialVelocity);
  } else {
    const dampedAngularFreq = undampedAngularFreq * Math.sqrt(dampingRatio * dampingRatio - 1);
    resolveSpring = (t) => {
      const envelope = Math.exp(-dampingRatio * undampedAngularFreq * t);
      const freqForT = Math.min(dampedAngularFreq * t, 300);
      return target - envelope * ((initialVelocity + dampingRatio * undampedAngularFreq * initialDelta) * Math.sinh(freqForT) + dampedAngularFreq * initialDelta * Math.cosh(freqForT)) / dampedAngularFreq;
    };
    const P = (initialVelocity + dampingRatio * undampedAngularFreq * initialDelta) / dampedAngularFreq;
    const sinhCoeff = dampingRatio * undampedAngularFreq * P - initialDelta * dampedAngularFreq;
    const coshCoeff = dampingRatio * undampedAngularFreq * initialDelta - P * dampedAngularFreq;
    resolveVelocity = (t) => {
      const envelope = Math.exp(-dampingRatio * undampedAngularFreq * t);
      const freqForT = Math.min(dampedAngularFreq * t, 300);
      return envelope * (sinhCoeff * Math.sinh(freqForT) + coshCoeff * Math.cosh(freqForT));
    };
  }
  const generator = {
    calculatedDuration: isResolvedFromDuration ? duration || null : null,
    velocity: (t) => secondsToMilliseconds(resolveVelocity(t)),
    next: (t) => {
      if (!isResolvedFromDuration && dampingRatio < 1) {
        const envelope = Math.exp(-dampingRatio * undampedAngularFreq * t);
        const sin = Math.sin(angularFreq * t);
        const cos = Math.cos(angularFreq * t);
        const current3 = target - envelope * (A * sin + initialDelta * cos);
        const currentVelocity = secondsToMilliseconds(envelope * (sinCoeff * sin + cosCoeff * cos));
        state.done = Math.abs(currentVelocity) <= restSpeed && Math.abs(target - current3) <= restDelta;
        state.value = state.done ? target : current3;
        return state;
      }
      const current2 = resolveSpring(t);
      if (!isResolvedFromDuration) {
        const currentVelocity = secondsToMilliseconds(resolveVelocity(t));
        state.done = Math.abs(currentVelocity) <= restSpeed && Math.abs(target - current2) <= restDelta;
      } else {
        state.done = t >= duration;
      }
      state.value = state.done ? target : current2;
      return state;
    },
    toString: () => {
      const calculatedDuration = Math.min(calcGeneratorDuration(generator), maxGeneratorDuration);
      const easing = generateLinearEasing((progress2) => generator.next(calculatedDuration * progress2).value, calculatedDuration, 30);
      return calculatedDuration + "ms " + easing;
    },
    toTransition: () => {
    }
  };
  return generator;
}
spring.applyToOptions = (options) => {
  const generatorOptions = createGeneratorEasing(options, 100, spring);
  options.ease = generatorOptions.ease;
  options.duration = secondsToMilliseconds(generatorOptions.duration);
  options.type = "keyframes";
  return options;
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/generators/utils/velocity.mjs
var velocitySampleDuration = 5;
function getGeneratorVelocity(resolveValue, t, current2) {
  const prevT = Math.max(t - velocitySampleDuration, 0);
  return velocityPerSecond(current2 - resolveValue(prevT), t - prevT);
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/generators/inertia.mjs
function inertia({ keyframes: keyframes2, velocity = 0, power = 0.8, timeConstant = 325, bounceDamping = 10, bounceStiffness = 500, modifyTarget, min, max, restDelta = 0.5, restSpeed }) {
  const origin = keyframes2[0];
  const state = {
    done: false,
    value: origin
  };
  const isOutOfBounds = (v) => min !== void 0 && v < min || max !== void 0 && v > max;
  const nearestBoundary = (v) => {
    if (min === void 0)
      return max;
    if (max === void 0)
      return min;
    return Math.abs(min - v) < Math.abs(max - v) ? min : max;
  };
  let amplitude = power * velocity;
  const ideal = origin + amplitude;
  const target = modifyTarget === void 0 ? ideal : modifyTarget(ideal);
  if (target !== ideal)
    amplitude = target - origin;
  const calcDelta = (t) => -amplitude * Math.exp(-t / timeConstant);
  const calcLatest = (t) => target + calcDelta(t);
  const applyFriction = (t) => {
    const delta = calcDelta(t);
    const latest = calcLatest(t);
    state.done = Math.abs(delta) <= restDelta;
    state.value = state.done ? target : latest;
  };
  let timeReachedBoundary;
  let spring$1;
  const checkCatchBoundary = (t) => {
    if (!isOutOfBounds(state.value))
      return;
    timeReachedBoundary = t;
    spring$1 = spring({
      keyframes: [state.value, nearestBoundary(state.value)],
      velocity: getGeneratorVelocity(calcLatest, t, state.value),
      // TODO: This should be passing * 1000
      damping: bounceDamping,
      stiffness: bounceStiffness,
      restDelta,
      restSpeed
    });
  };
  checkCatchBoundary(0);
  return {
    calculatedDuration: null,
    next: (t) => {
      let hasUpdatedFrame = false;
      if (!spring$1 && timeReachedBoundary === void 0) {
        hasUpdatedFrame = true;
        applyFriction(t);
        checkCatchBoundary(t);
      }
      if (timeReachedBoundary !== void 0 && t >= timeReachedBoundary) {
        return spring$1.next(t - timeReachedBoundary);
      } else {
        !hasUpdatedFrame && applyFriction(t);
        return state;
      }
    }
  };
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/utils/interpolate.mjs
function createMixers(output, ease3, customMixer) {
  const mixers = [];
  const mixerFactory = customMixer || MotionGlobalConfig.mix || mix;
  const numMixers = output.length - 1;
  for (let i = 0; i < numMixers; i++) {
    let mixer = mixerFactory(output[i], output[i + 1]);
    if (ease3) {
      const easingFunction = Array.isArray(ease3) ? ease3[i] || noop : ease3;
      mixer = pipe(easingFunction, mixer);
    }
    mixers.push(mixer);
  }
  return mixers;
}
function interpolate(input, output, { clamp: isClamp = true, ease: ease3, mixer } = {}) {
  const inputLength = input.length;
  invariant(inputLength === output.length, "Both input and output ranges must be the same length", "range-length");
  if (inputLength === 1)
    return () => output[0];
  if (inputLength === 2 && output[0] === output[1])
    return () => output[1];
  const isZeroDeltaRange = input[0] === input[1];
  if (input[0] > input[inputLength - 1]) {
    input = [...input].reverse();
    output = [...output].reverse();
  }
  const mixers = createMixers(output, ease3, mixer);
  const numMixers = mixers.length;
  const interpolator = (v) => {
    if (isZeroDeltaRange && v < input[0])
      return output[0];
    let i = 0;
    if (numMixers > 1) {
      for (; i < input.length - 2; i++) {
        if (v < input[i + 1])
          break;
      }
    }
    const progressInRange = progress(input[i], input[i + 1], v);
    return mixers[i](progressInRange);
  };
  return isClamp ? (v) => interpolator(clamp(input[0], input[inputLength - 1], v)) : interpolator;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/keyframes/offsets/fill.mjs
function fillOffset(offset, remaining) {
  const min = offset[offset.length - 1];
  for (let i = 1; i <= remaining; i++) {
    const offsetProgress = progress(0, remaining, i);
    offset.push(mixNumber(min, 1, offsetProgress));
  }
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/keyframes/offsets/default.mjs
function defaultOffset(arr) {
  const offset = [0];
  fillOffset(offset, arr.length - 1);
  return offset;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/keyframes/offsets/time.mjs
function convertOffsetToTimes(offset, duration) {
  return offset.map((o) => o * duration);
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/generators/keyframes.mjs
function defaultEasing(values, easing) {
  return values.map(() => easing || easeInOut).splice(0, values.length - 1);
}
function keyframes({ duration = 300, keyframes: keyframeValues, times, ease: ease3 = "easeInOut" }) {
  const easingFunctions = isEasingArray(ease3) ? ease3.map(easingDefinitionToFunction) : easingDefinitionToFunction(ease3);
  const state = {
    done: false,
    value: keyframeValues[0]
  };
  const absoluteTimes = convertOffsetToTimes(
    // Only use the provided offsets if they're the correct length
    // TODO Maybe we should warn here if there's a length mismatch
    times && times.length === keyframeValues.length ? times : defaultOffset(keyframeValues),
    duration
  );
  const mapTimeToKeyframe = interpolate(absoluteTimes, keyframeValues, {
    ease: Array.isArray(easingFunctions) ? easingFunctions : defaultEasing(keyframeValues, easingFunctions)
  });
  return {
    calculatedDuration: duration,
    next: (t) => {
      state.value = mapTimeToKeyframe(t);
      state.done = t >= duration;
      return state;
    }
  };
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/keyframes/get-final.mjs
var isNotNull = (value) => value !== null;
function getFinalKeyframe(keyframes2, { repeat, repeatType = "loop" }, finalKeyframe, speed = 1) {
  const resolvedKeyframes = keyframes2.filter(isNotNull);
  const useFirstKeyframe = speed < 0 || repeat && repeatType !== "loop" && repeat % 2 === 1;
  const index = useFirstKeyframe ? 0 : resolvedKeyframes.length - 1;
  return !index || finalKeyframe === void 0 ? resolvedKeyframes[index] : finalKeyframe;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/utils/replace-transition-type.mjs
var transitionTypeMap = {
  decay: inertia,
  inertia,
  tween: keyframes,
  keyframes,
  spring
};
function replaceTransitionType(transition) {
  if (typeof transition.type === "string") {
    transition.type = transitionTypeMap[transition.type];
  }
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/utils/WithPromise.mjs
var WithPromise = class {
  constructor() {
    this.updateFinished();
  }
  get finished() {
    return this._finished;
  }
  updateFinished() {
    this._finished = new Promise((resolve3) => {
      this.resolve = resolve3;
    });
  }
  notifyFinished() {
    this.resolve();
  }
  /**
   * Allows the animation to be awaited.
   *
   * @deprecated Use `finished` instead.
   */
  then(onResolve, onReject) {
    return this.finished.then(onResolve, onReject);
  }
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/JSAnimation.mjs
var percentToProgress = (percent2) => percent2 / 100;
var JSAnimation = class extends WithPromise {
  constructor(options) {
    super();
    this.state = "idle";
    this.startTime = null;
    this.isStopped = false;
    this.currentTime = 0;
    this.holdTime = null;
    this.playbackSpeed = 1;
    this.delayState = {
      done: false,
      value: void 0
    };
    this.stop = () => {
      const { motionValue: motionValue2 } = this.options;
      if (motionValue2 && motionValue2.updatedAt !== time.now()) {
        this.tick(time.now());
      }
      this.isStopped = true;
      if (this.state === "idle")
        return;
      this.teardown();
      this.options.onStop?.();
    };
    this.options = options;
    this.initAnimation();
    this.play();
    if (options.autoplay === false)
      this.pause();
  }
  initAnimation() {
    const { options } = this;
    replaceTransitionType(options);
    const { type = keyframes, repeat = 0, repeatDelay = 0, repeatType, velocity = 0 } = options;
    let { keyframes: keyframes$1 } = options;
    const generatorFactory = type || keyframes;
    if (generatorFactory !== keyframes) {
      invariant(keyframes$1.length <= 2, `Only two keyframes currently supported with spring and inertia animations. Trying to animate ${keyframes$1}`, "spring-two-frames");
    }
    if (generatorFactory !== keyframes && typeof keyframes$1[0] !== "number") {
      this.mixKeyframes = pipe(percentToProgress, mix(keyframes$1[0], keyframes$1[1]));
      keyframes$1 = [0, 100];
    }
    const generator = generatorFactory({ ...options, keyframes: keyframes$1 });
    if (repeatType === "mirror") {
      this.mirroredGenerator = generatorFactory({
        ...options,
        keyframes: [...keyframes$1].reverse(),
        velocity: -velocity
      });
    }
    if (generator.calculatedDuration === null) {
      generator.calculatedDuration = calcGeneratorDuration(generator);
    }
    const { calculatedDuration } = generator;
    this.calculatedDuration = calculatedDuration;
    this.resolvedDuration = calculatedDuration + repeatDelay;
    this.totalDuration = this.resolvedDuration * (repeat + 1) - repeatDelay;
    this.generator = generator;
  }
  updateTime(timestamp) {
    const animationTime = Math.round(timestamp - this.startTime) * this.playbackSpeed;
    if (this.holdTime !== null) {
      this.currentTime = this.holdTime;
    } else {
      this.currentTime = animationTime;
    }
  }
  tick(timestamp, sample = false) {
    const { generator, totalDuration, mixKeyframes, mirroredGenerator, resolvedDuration, calculatedDuration } = this;
    if (this.startTime === null)
      return generator.next(0);
    const { delay: delay2 = 0, keyframes: keyframes2, repeat, repeatType, repeatDelay, type, onUpdate, finalKeyframe } = this.options;
    if (this.speed > 0) {
      this.startTime = Math.min(this.startTime, timestamp);
    } else if (this.speed < 0) {
      this.startTime = Math.min(timestamp - totalDuration / this.speed, this.startTime);
    }
    if (sample) {
      this.currentTime = timestamp;
    } else {
      this.updateTime(timestamp);
    }
    const timeWithoutDelay = this.currentTime - delay2 * (this.playbackSpeed >= 0 ? 1 : -1);
    const isInDelayPhase = this.playbackSpeed >= 0 ? timeWithoutDelay < 0 : timeWithoutDelay > totalDuration;
    this.currentTime = Math.max(timeWithoutDelay, 0);
    if (this.state === "finished" && this.holdTime === null) {
      this.currentTime = totalDuration;
    }
    let elapsed = this.currentTime;
    let frameGenerator = generator;
    if (repeat) {
      const progress2 = Math.min(this.currentTime, totalDuration) / resolvedDuration;
      let currentIteration = Math.floor(progress2);
      let iterationProgress = progress2 % 1;
      if (!iterationProgress && progress2 >= 1) {
        iterationProgress = 1;
      }
      iterationProgress === 1 && currentIteration--;
      currentIteration = Math.min(currentIteration, repeat + 1);
      const isOddIteration = Boolean(currentIteration % 2);
      if (isOddIteration) {
        if (repeatType === "reverse") {
          iterationProgress = 1 - iterationProgress;
          if (repeatDelay) {
            iterationProgress -= repeatDelay / resolvedDuration;
          }
        } else if (repeatType === "mirror") {
          frameGenerator = mirroredGenerator;
        }
      }
      elapsed = clamp(0, 1, iterationProgress) * resolvedDuration;
    }
    let state;
    if (isInDelayPhase) {
      this.delayState.value = keyframes2[0];
      state = this.delayState;
    } else {
      state = frameGenerator.next(elapsed);
    }
    if (mixKeyframes && !isInDelayPhase) {
      state.value = mixKeyframes(state.value);
    }
    let { done } = state;
    if (!isInDelayPhase && calculatedDuration !== null) {
      done = this.playbackSpeed >= 0 ? this.currentTime >= totalDuration : this.currentTime <= 0;
    }
    const isAnimationFinished = this.holdTime === null && (this.state === "finished" || this.state === "running" && done);
    if (isAnimationFinished && type !== inertia) {
      state.value = getFinalKeyframe(keyframes2, this.options, finalKeyframe, this.speed);
    }
    if (onUpdate) {
      onUpdate(state.value);
    }
    if (isAnimationFinished) {
      this.finish();
    }
    return state;
  }
  /**
   * Allows the returned animation to be awaited or promise-chained. Currently
   * resolves when the animation finishes at all but in a future update could/should
   * reject if its cancels.
   */
  then(resolve3, reject) {
    return this.finished.then(resolve3, reject);
  }
  get duration() {
    return millisecondsToSeconds(this.calculatedDuration);
  }
  get iterationDuration() {
    const { delay: delay2 = 0 } = this.options || {};
    return this.duration + millisecondsToSeconds(delay2);
  }
  get time() {
    return millisecondsToSeconds(this.currentTime);
  }
  set time(newTime) {
    newTime = secondsToMilliseconds(newTime);
    this.currentTime = newTime;
    if (this.startTime === null || this.holdTime !== null || this.playbackSpeed === 0) {
      this.holdTime = newTime;
    } else if (this.driver) {
      this.startTime = this.driver.now() - newTime / this.playbackSpeed;
    }
    if (this.driver) {
      this.driver.start(false);
    } else {
      this.startTime = 0;
      this.state = "paused";
      this.holdTime = newTime;
      this.tick(newTime);
    }
  }
  /**
   * Returns the generator's velocity at the current time in units/second.
   * Uses the analytical derivative when available (springs), avoiding
   * the MotionValue's frame-dependent velocity estimation.
   */
  getGeneratorVelocity() {
    const t = this.currentTime;
    if (t <= 0)
      return this.options.velocity || 0;
    if (this.generator.velocity) {
      return this.generator.velocity(t);
    }
    const current2 = this.generator.next(t).value;
    return getGeneratorVelocity((s) => this.generator.next(s).value, t, current2);
  }
  get speed() {
    return this.playbackSpeed;
  }
  set speed(newSpeed) {
    const hasChanged = this.playbackSpeed !== newSpeed;
    if (hasChanged && this.driver) {
      this.updateTime(time.now());
    }
    this.playbackSpeed = newSpeed;
    if (hasChanged && this.driver) {
      this.time = millisecondsToSeconds(this.currentTime);
    }
  }
  play() {
    if (this.isStopped)
      return;
    const { driver = frameloopDriver, startTime } = this.options;
    if (!this.driver) {
      this.driver = driver((timestamp) => this.tick(timestamp));
    }
    this.options.onPlay?.();
    const now2 = this.driver.now();
    if (this.state === "finished") {
      this.updateFinished();
      this.startTime = now2;
    } else if (this.holdTime !== null) {
      this.startTime = now2 - this.holdTime;
    } else if (!this.startTime) {
      this.startTime = startTime ?? now2;
    }
    if (this.state === "finished" && this.speed < 0) {
      this.startTime += this.calculatedDuration;
    }
    this.holdTime = null;
    this.state = "running";
    this.driver.start();
  }
  pause() {
    this.state = "paused";
    this.updateTime(time.now());
    this.holdTime = this.currentTime;
  }
  complete() {
    if (this.state !== "running") {
      this.play();
    }
    this.state = "finished";
    this.holdTime = null;
  }
  finish() {
    this.notifyFinished();
    this.teardown();
    this.state = "finished";
    this.options.onComplete?.();
  }
  cancel() {
    this.holdTime = null;
    this.startTime = 0;
    this.tick(0);
    this.teardown();
    this.options.onCancel?.();
  }
  teardown() {
    this.state = "idle";
    this.stopDriver();
    this.startTime = this.holdTime = null;
  }
  stopDriver() {
    if (!this.driver)
      return;
    this.driver.stop();
    this.driver = void 0;
  }
  sample(sampleTime) {
    this.startTime = 0;
    return this.tick(sampleTime, true);
  }
  attachTimeline(timeline) {
    if (this.options.allowFlatten) {
      this.options.type = "keyframes";
      this.options.ease = "linear";
      this.initAnimation();
    }
    this.driver?.stop();
    return timeline.observe(this);
  }
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/keyframes/utils/fill-wildcards.mjs
function fillWildcards(keyframes2) {
  for (let i = 1; i < keyframes2.length; i++) {
    keyframes2[i] ?? (keyframes2[i] = keyframes2[i - 1]);
  }
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/dom/parse-transform.mjs
var radToDeg = (rad) => rad * 180 / Math.PI;
var rotate = (v) => {
  const angle = radToDeg(Math.atan2(v[1], v[0]));
  return rebaseAngle(angle);
};
var matrix2dParsers = {
  x: 4,
  y: 5,
  translateX: 4,
  translateY: 5,
  scaleX: 0,
  scaleY: 3,
  scale: (v) => (Math.abs(v[0]) + Math.abs(v[3])) / 2,
  rotate,
  rotateZ: rotate,
  skewX: (v) => radToDeg(Math.atan(v[1])),
  skewY: (v) => radToDeg(Math.atan(v[2])),
  skew: (v) => (Math.abs(v[1]) + Math.abs(v[2])) / 2
};
var rebaseAngle = (angle) => {
  angle = angle % 360;
  if (angle < 0)
    angle += 360;
  return angle;
};
var rotateZ = rotate;
var scaleX = (v) => Math.sqrt(v[0] * v[0] + v[1] * v[1]);
var scaleY = (v) => Math.sqrt(v[4] * v[4] + v[5] * v[5]);
var matrix3dParsers = {
  x: 12,
  y: 13,
  z: 14,
  translateX: 12,
  translateY: 13,
  translateZ: 14,
  scaleX,
  scaleY,
  scale: (v) => (scaleX(v) + scaleY(v)) / 2,
  rotateX: (v) => rebaseAngle(radToDeg(Math.atan2(v[6], v[5]))),
  rotateY: (v) => rebaseAngle(radToDeg(Math.atan2(-v[2], v[0]))),
  rotateZ,
  rotate: rotateZ,
  skewX: (v) => radToDeg(Math.atan(v[4])),
  skewY: (v) => radToDeg(Math.atan(v[1])),
  skew: (v) => (Math.abs(v[1]) + Math.abs(v[4])) / 2
};
function defaultTransformValue(name) {
  return name.includes("scale") ? 1 : 0;
}
function parseValueFromTransform(transform, name) {
  if (!transform || transform === "none") {
    return defaultTransformValue(name);
  }
  const matrix3dMatch = transform.match(/^matrix3d\(([-\d.e\s,]+)\)$/u);
  let parsers;
  let match2;
  if (matrix3dMatch) {
    parsers = matrix3dParsers;
    match2 = matrix3dMatch;
  } else {
    const matrix2dMatch = transform.match(/^matrix\(([-\d.e\s,]+)\)$/u);
    parsers = matrix2dParsers;
    match2 = matrix2dMatch;
  }
  if (!match2) {
    return defaultTransformValue(name);
  }
  const valueParser = parsers[name];
  const values = match2[1].split(",").map(convertTransformToNumber);
  return typeof valueParser === "function" ? valueParser(values) : values[valueParser];
}
var readTransformValue = (instance, name) => {
  const { transform = "none" } = getComputedStyle(instance);
  return parseValueFromTransform(transform, name);
};
function convertTransformToNumber(value) {
  return parseFloat(value.trim());
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/utils/keys-transform.mjs
var transformPropOrder = [
  "transformPerspective",
  "x",
  "y",
  "z",
  "translateX",
  "translateY",
  "translateZ",
  "scale",
  "scaleX",
  "scaleY",
  "rotate",
  "rotateX",
  "rotateY",
  "rotateZ",
  "skew",
  "skewX",
  "skewY"
];
var transformProps = /* @__PURE__ */ (() => /* @__PURE__ */ new Set([...transformPropOrder, "pathRotation"]))();

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/keyframes/utils/unit-conversion.mjs
var isNumOrPxType = (v) => v === number || v === px;
var transformKeys = /* @__PURE__ */ new Set(["x", "y", "z"]);
var nonTranslationalTransformKeys = transformPropOrder.filter((key) => !transformKeys.has(key));
function removeNonTranslationalTransform(visualElement) {
  const removedTransforms = [];
  nonTranslationalTransformKeys.forEach((key) => {
    const value = visualElement.getValue(key);
    if (value !== void 0) {
      removedTransforms.push([key, value.get()]);
      value.set(key.startsWith("scale") ? 1 : 0);
    }
  });
  return removedTransforms;
}
var positionalValues = {
  // Dimensions
  width: ({ x }, { paddingLeft = "0", paddingRight = "0", boxSizing }) => {
    const width = x.max - x.min;
    return boxSizing === "border-box" ? width : width - parseFloat(paddingLeft) - parseFloat(paddingRight);
  },
  height: ({ y }, { paddingTop = "0", paddingBottom = "0", boxSizing }) => {
    const height = y.max - y.min;
    return boxSizing === "border-box" ? height : height - parseFloat(paddingTop) - parseFloat(paddingBottom);
  },
  top: (_bbox, { top }) => parseFloat(top),
  left: (_bbox, { left }) => parseFloat(left),
  bottom: ({ y }, { top }) => parseFloat(top) + (y.max - y.min),
  right: ({ x }, { left }) => parseFloat(left) + (x.max - x.min),
  // Transform
  x: (_bbox, { transform }) => parseValueFromTransform(transform, "x"),
  y: (_bbox, { transform }) => parseValueFromTransform(transform, "y")
};
positionalValues.translateX = positionalValues.x;
positionalValues.translateY = positionalValues.y;

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/keyframes/KeyframesResolver.mjs
var toResolve = /* @__PURE__ */ new Set();
var isScheduled = false;
var anyNeedsMeasurement = false;
var isForced = false;
function measureAllKeyframes() {
  if (anyNeedsMeasurement) {
    const resolversToMeasure = Array.from(toResolve).filter((resolver) => resolver.needsMeasurement);
    const elementsToMeasure = new Set(resolversToMeasure.map((resolver) => resolver.element));
    const transformsToRestore = /* @__PURE__ */ new Map();
    elementsToMeasure.forEach((element) => {
      const removedTransforms = removeNonTranslationalTransform(element);
      if (!removedTransforms.length)
        return;
      transformsToRestore.set(element, removedTransforms);
      element.render();
    });
    resolversToMeasure.forEach((resolver) => resolver.measureInitialState());
    elementsToMeasure.forEach((element) => {
      element.render();
      const restore = transformsToRestore.get(element);
      if (restore) {
        restore.forEach(([key, value]) => {
          element.getValue(key)?.set(value);
        });
      }
    });
    resolversToMeasure.forEach((resolver) => resolver.measureEndState());
    resolversToMeasure.forEach((resolver) => {
      if (resolver.suspendedScrollY !== void 0) {
        window.scrollTo(0, resolver.suspendedScrollY);
      }
    });
  }
  anyNeedsMeasurement = false;
  isScheduled = false;
  toResolve.forEach((resolver) => resolver.complete(isForced));
  toResolve.clear();
}
function readAllKeyframes() {
  toResolve.forEach((resolver) => {
    resolver.readKeyframes();
    if (resolver.needsMeasurement) {
      anyNeedsMeasurement = true;
    }
  });
}
function flushKeyframeResolvers() {
  isForced = true;
  readAllKeyframes();
  measureAllKeyframes();
  isForced = false;
}
var KeyframeResolver = class {
  constructor(unresolvedKeyframes, onComplete, name, motionValue2, element, isAsync = false) {
    this.state = "pending";
    this.isAsync = false;
    this.needsMeasurement = false;
    this.unresolvedKeyframes = [...unresolvedKeyframes];
    this.onComplete = onComplete;
    this.name = name;
    this.motionValue = motionValue2;
    this.element = element;
    this.isAsync = isAsync;
  }
  scheduleResolve() {
    this.state = "scheduled";
    if (this.isAsync) {
      toResolve.add(this);
      if (!isScheduled) {
        isScheduled = true;
        frame.read(readAllKeyframes);
        frame.resolveKeyframes(measureAllKeyframes);
      }
    } else {
      this.readKeyframes();
      this.complete();
    }
  }
  readKeyframes() {
    const { unresolvedKeyframes, name, element, motionValue: motionValue2 } = this;
    if (unresolvedKeyframes[0] === null) {
      const currentValue2 = motionValue2?.get();
      const finalKeyframe = unresolvedKeyframes[unresolvedKeyframes.length - 1];
      if (currentValue2 !== void 0) {
        unresolvedKeyframes[0] = currentValue2;
      } else if (element && name) {
        const valueAsRead = element.readValue(name, finalKeyframe);
        if (valueAsRead !== void 0 && valueAsRead !== null) {
          unresolvedKeyframes[0] = valueAsRead;
        }
      }
      if (unresolvedKeyframes[0] === void 0) {
        unresolvedKeyframes[0] = finalKeyframe;
      }
      if (motionValue2 && currentValue2 === void 0) {
        motionValue2.set(unresolvedKeyframes[0]);
      }
    }
    fillWildcards(unresolvedKeyframes);
  }
  setFinalKeyframe() {
  }
  measureInitialState() {
  }
  renderEndStyles() {
  }
  measureEndState() {
  }
  complete(isForcedComplete = false) {
    this.state = "complete";
    this.onComplete(this.unresolvedKeyframes, this.finalKeyframe, isForcedComplete);
    toResolve.delete(this);
  }
  cancel() {
    if (this.state === "scheduled") {
      toResolve.delete(this);
      this.state = "pending";
    }
  }
  resume() {
    if (this.state === "pending")
      this.scheduleResolve();
  }
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/dom/is-css-var.mjs
var isCSSVar = (name) => name.startsWith("--");

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/dom/style-set.mjs
function setStyle(element, name, value) {
  isCSSVar(name) ? element.style.setProperty(name, value) : element.style[name] = value;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/utils/supports/flags.mjs
var supportsFlags = {};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/utils/supports/memo.mjs
function memoSupports(callback, supportsFlag) {
  const memoized = memo(callback);
  return () => supportsFlags[supportsFlag] ?? memoized();
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/utils/supports/scroll-timeline.mjs
var supportsScrollTimeline = /* @__PURE__ */ memoSupports(() => window.ScrollTimeline !== void 0, "scrollTimeline");
var supportsViewTimeline = /* @__PURE__ */ memoSupports(() => window.ViewTimeline !== void 0, "viewTimeline");

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/utils/supports/linear-easing.mjs
var supportsLinearEasing = /* @__PURE__ */ memoSupports(() => {
  try {
    document.createElement("div").animate({ opacity: 0 }, { easing: "linear(0, 1)" });
  } catch (e) {
    return false;
  }
  return true;
}, "linearEasing");

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/waapi/easing/cubic-bezier.mjs
var cubicBezierAsString = ([a, b, c, d]) => `cubic-bezier(${a}, ${b}, ${c}, ${d})`;

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/waapi/easing/supported.mjs
var supportedWaapiEasing = {
  linear: "linear",
  ease: "ease",
  easeIn: "ease-in",
  easeOut: "ease-out",
  easeInOut: "ease-in-out",
  circIn: /* @__PURE__ */ cubicBezierAsString([0, 0.65, 0.55, 1]),
  circOut: /* @__PURE__ */ cubicBezierAsString([0.55, 0, 1, 0.45]),
  backIn: /* @__PURE__ */ cubicBezierAsString([0.31, 0.01, 0.66, -0.59]),
  backOut: /* @__PURE__ */ cubicBezierAsString([0.33, 1.53, 0.69, 0.99])
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/waapi/easing/map-easing.mjs
function mapEasingToNativeEasing(easing, duration) {
  if (!easing) {
    return void 0;
  } else if (typeof easing === "function") {
    return supportsLinearEasing() ? generateLinearEasing(easing, duration) : "ease-out";
  } else if (isBezierDefinition(easing)) {
    return cubicBezierAsString(easing);
  } else if (Array.isArray(easing)) {
    return easing.map((segmentEasing) => mapEasingToNativeEasing(segmentEasing, duration) || supportedWaapiEasing.easeOut);
  } else {
    return supportedWaapiEasing[easing];
  }
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/waapi/start-waapi-animation.mjs
function startWaapiAnimation(element, valueName, keyframes2, { delay: delay2 = 0, duration = 300, repeat = 0, repeatType = "loop", ease: ease3 = "easeOut", times } = {}, pseudoElement = void 0) {
  const keyframeOptions = {
    [valueName]: keyframes2
  };
  if (times)
    keyframeOptions.offset = times;
  const easing = mapEasingToNativeEasing(ease3, duration);
  if (Array.isArray(easing))
    keyframeOptions.easing = easing;
  const options = {
    delay: delay2,
    duration,
    easing: !Array.isArray(easing) ? easing : "linear",
    fill: "both",
    iterations: repeat + 1,
    direction: repeatType === "reverse" ? "alternate" : "normal"
  };
  if (pseudoElement)
    options.pseudoElement = pseudoElement;
  return element.animate(keyframeOptions, options);
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/generators/utils/is-generator.mjs
function isGenerator(type) {
  return typeof type === "function" && "applyToOptions" in type;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/waapi/utils/apply-generator.mjs
function applyGeneratorOptions({ type, ...options }) {
  if (isGenerator(type) && supportsLinearEasing()) {
    return type.applyToOptions(options);
  } else {
    options.duration ?? (options.duration = 300);
    options.ease ?? (options.ease = "easeOut");
  }
  return options;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/NativeAnimation.mjs
var NativeAnimation = class extends WithPromise {
  constructor(options) {
    super();
    this.finishedTime = null;
    this.isStopped = false;
    this.manualStartTime = null;
    if (!options)
      return;
    const { element, name, keyframes: keyframes2, pseudoElement, allowFlatten = false, finalKeyframe, onComplete } = options;
    this.isPseudoElement = Boolean(pseudoElement);
    this.allowFlatten = allowFlatten;
    this.options = options;
    invariant(typeof options.type !== "string", `Mini animate() doesn't support "type" as a string.`, "mini-spring");
    const transition = applyGeneratorOptions(options);
    this.animation = startWaapiAnimation(element, name, keyframes2, transition, pseudoElement);
    if (transition.autoplay === false) {
      this.animation.pause();
    }
    this.animation.onfinish = () => {
      this.finishedTime = this.time;
      if (!pseudoElement) {
        const keyframe = getFinalKeyframe(keyframes2, this.options, finalKeyframe, this.speed);
        if (this.updateMotionValue) {
          this.updateMotionValue(keyframe);
        }
        setStyle(element, name, keyframe);
        this.animation.cancel();
      }
      onComplete?.();
      this.notifyFinished();
    };
  }
  play() {
    if (this.isStopped)
      return;
    this.manualStartTime = null;
    this.animation.play();
    if (this.state === "finished") {
      this.updateFinished();
    }
  }
  pause() {
    this.animation.pause();
  }
  complete() {
    this.animation.finish?.();
  }
  cancel() {
    try {
      this.animation.cancel();
    } catch (e) {
    }
  }
  stop() {
    if (this.isStopped)
      return;
    this.isStopped = true;
    const { state } = this;
    if (state === "idle" || state === "finished") {
      return;
    }
    if (this.updateMotionValue) {
      this.updateMotionValue();
    } else {
      this.commitStyles();
    }
    if (!this.isPseudoElement)
      this.cancel();
  }
  /**
   * WAAPI doesn't natively have any interruption capabilities.
   *
   * In this method, we commit styles back to the DOM before cancelling
   * the animation.
   *
   * This is designed to be overridden by NativeAnimationExtended, which
   * will create a renderless JS animation and sample it twice to calculate
   * its current value, "previous" value, and therefore allow
   * Motion to also correctly calculate velocity for any subsequent animation
   * while deferring the commit until the next animation frame.
   */
  commitStyles() {
    const element = this.options?.element;
    if (!this.isPseudoElement && element?.isConnected) {
      this.animation.commitStyles?.();
    }
  }
  get duration() {
    const duration = this.animation.effect?.getComputedTiming?.().duration || 0;
    return millisecondsToSeconds(Number(duration));
  }
  get iterationDuration() {
    const { delay: delay2 = 0 } = this.options || {};
    return this.duration + millisecondsToSeconds(delay2);
  }
  get time() {
    return millisecondsToSeconds(Number(this.animation.currentTime) || 0);
  }
  set time(newTime) {
    const wasFinished = this.finishedTime !== null;
    this.manualStartTime = null;
    this.finishedTime = null;
    this.animation.currentTime = secondsToMilliseconds(newTime);
    if (wasFinished) {
      this.animation.pause();
    }
  }
  /**
   * The playback speed of the animation.
   * 1 = normal speed, 2 = double speed, 0.5 = half speed.
   */
  get speed() {
    return this.animation.playbackRate;
  }
  set speed(newSpeed) {
    if (newSpeed < 0)
      this.finishedTime = null;
    this.animation.playbackRate = newSpeed;
  }
  get state() {
    return this.finishedTime !== null ? "finished" : this.animation.playState;
  }
  get startTime() {
    return this.manualStartTime ?? Number(this.animation.startTime);
  }
  set startTime(newStartTime) {
    this.manualStartTime = this.animation.startTime = newStartTime;
  }
  /**
   * Attaches a timeline to the animation, for instance the `ScrollTimeline`.
   */
  attachTimeline({ timeline, rangeStart, rangeEnd, observe }) {
    if (this.allowFlatten) {
      this.animation.effect?.updateTiming({ easing: "linear" });
    }
    this.animation.onfinish = null;
    if (timeline && supportsScrollTimeline()) {
      this.animation.timeline = timeline;
      if (rangeStart)
        this.animation.rangeStart = rangeStart;
      if (rangeEnd)
        this.animation.rangeEnd = rangeEnd;
      return noop;
    } else {
      return observe(this);
    }
  }
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/waapi/utils/unsupported-easing.mjs
var unsupportedEasingFunctions = {
  anticipate,
  backInOut,
  circInOut
};
function isUnsupportedEase(key) {
  return key in unsupportedEasingFunctions;
}
function replaceStringEasing(transition) {
  if (typeof transition.ease === "string" && isUnsupportedEase(transition.ease)) {
    transition.ease = unsupportedEasingFunctions[transition.ease];
  }
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/NativeAnimationExtended.mjs
var sampleDelta = 10;
var NativeAnimationExtended = class extends NativeAnimation {
  constructor(options) {
    replaceStringEasing(options);
    replaceTransitionType(options);
    super(options);
    if (options.startTime !== void 0 && options.autoplay !== false) {
      this.startTime = options.startTime;
    }
    this.options = options;
  }
  /**
   * WAAPI doesn't natively have any interruption capabilities.
   *
   * Rather than read committed styles back out of the DOM, we can
   * create a renderless JS animation and sample it twice to calculate
   * its current value, "previous" value, and therefore allow
   * Motion to calculate velocity for any subsequent animation.
   */
  updateMotionValue(value) {
    const { motionValue: motionValue2, onUpdate, onComplete, element, ...options } = this.options;
    if (!motionValue2)
      return;
    if (value !== void 0) {
      motionValue2.set(value);
      return;
    }
    const sampleAnimation = new JSAnimation({
      ...options,
      autoplay: false
    });
    const sampleTime = Math.max(sampleDelta, time.now() - this.startTime);
    const delta = clamp(0, sampleDelta, sampleTime - sampleDelta);
    const current2 = sampleAnimation.sample(sampleTime).value;
    const { name } = this.options;
    if (element && name)
      setStyle(element, name, current2);
    motionValue2.setWithVelocity(sampleAnimation.sample(Math.max(0, sampleTime - delta)).value, current2, delta);
    sampleAnimation.stop();
  }
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/utils/is-animatable.mjs
var isAnimatable = (value, name) => {
  if (name === "zIndex")
    return false;
  if (typeof value === "number" || Array.isArray(value))
    return true;
  if (typeof value === "string" && // It's animatable if we have a string
  (complex.test(value) || value === "0") && // And it contains numbers and/or colors
  !value.startsWith("url(")) {
    return true;
  }
  return false;
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/utils/can-animate.mjs
function hasKeyframesChanged(keyframes2) {
  const current2 = keyframes2[0];
  if (keyframes2.length === 1)
    return true;
  for (let i = 0; i < keyframes2.length; i++) {
    if (keyframes2[i] !== current2)
      return true;
  }
}
function canAnimate(keyframes2, name, type, velocity) {
  const originKeyframe = keyframes2[0];
  if (originKeyframe === null) {
    return false;
  }
  if (name === "display" || name === "visibility")
    return true;
  const targetKeyframe = keyframes2[keyframes2.length - 1];
  const isOriginAnimatable = isAnimatable(originKeyframe, name);
  const isTargetAnimatable = isAnimatable(targetKeyframe, name);
  warning(isOriginAnimatable === isTargetAnimatable, `You are trying to animate ${name} from "${originKeyframe}" to "${targetKeyframe}". "${isOriginAnimatable ? targetKeyframe : originKeyframe}" is not an animatable value.`, "value-not-animatable");
  if (!isOriginAnimatable || !isTargetAnimatable) {
    return false;
  }
  return hasKeyframesChanged(keyframes2) || (type === "spring" || isGenerator(type)) && velocity;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/utils/make-animation-instant.mjs
function makeAnimationInstant(options) {
  options.duration = 0;
  options.type = "keyframes";
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/waapi/utils/accelerated-values.mjs
var acceleratedValues = /* @__PURE__ */ new Set([
  "opacity",
  "clipPath",
  "filter",
  "transform",
  "backgroundColor"
]);

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/waapi/utils/is-browser-color.mjs
var browserColorFunctions = /^(?:oklch|oklab|lab|lch|color|color-mix|light-dark)\(/;
function hasBrowserOnlyColors(keyframes2) {
  for (let i = 0; i < keyframes2.length; i++) {
    if (typeof keyframes2[i] === "string" && browserColorFunctions.test(keyframes2[i])) {
      return true;
    }
  }
  return false;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/waapi/supports/waapi.mjs
var colorProperties = /* @__PURE__ */ new Set([
  "color",
  "backgroundColor",
  "outlineColor",
  "fill",
  "stroke",
  "borderColor",
  "borderTopColor",
  "borderRightColor",
  "borderBottomColor",
  "borderLeftColor"
]);
var supportsWaapi = /* @__PURE__ */ memo(() => Object.hasOwnProperty.call(Element.prototype, "animate"));
function supportsBrowserAnimation(options) {
  const { motionValue: motionValue2, name, repeatDelay, repeatType, damping, type, keyframes: keyframes2 } = options;
  const subject = motionValue2?.owner?.current;
  if (!(subject instanceof HTMLElement) && !(subject instanceof SVGElement)) {
    return false;
  }
  const { onUpdate, transformTemplate } = motionValue2.owner.getProps();
  return supportsWaapi() && name && /**
   * Force WAAPI for color properties with browser-only color formats
   * (oklch, oklab, lab, lch, etc.) that the JS animation path can't parse.
   */
  (acceleratedValues.has(name) || colorProperties.has(name) && hasBrowserOnlyColors(keyframes2)) && (name !== "transform" || !transformTemplate) && /**
   * If we're outputting values to onUpdate then we can't use WAAPI as there's
   * no way to read the value from WAAPI every frame.
   */
  !onUpdate && !repeatDelay && repeatType !== "mirror" && damping !== 0 && type !== "inertia";
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/AsyncMotionValueAnimation.mjs
var MAX_RESOLVE_DELAY = 40;
var AsyncMotionValueAnimation = class extends WithPromise {
  constructor({ autoplay = true, delay: delay2 = 0, type = "keyframes", repeat = 0, repeatDelay = 0, repeatType = "loop", keyframes: keyframes2, name, motionValue: motionValue2, element, ...options }) {
    super();
    this.stop = () => {
      if (this._animation) {
        this._animation.stop();
        this.stopTimeline?.();
      }
      this.keyframeResolver?.cancel();
    };
    this.createdAt = time.now();
    const optionsWithDefaults = {
      autoplay,
      delay: delay2,
      type,
      repeat,
      repeatDelay,
      repeatType,
      name,
      motionValue: motionValue2,
      element,
      ...options
    };
    const KeyframeResolver$1 = element?.KeyframeResolver || KeyframeResolver;
    this.keyframeResolver = new KeyframeResolver$1(keyframes2, (resolvedKeyframes, finalKeyframe, forced) => this.onKeyframesResolved(resolvedKeyframes, finalKeyframe, optionsWithDefaults, !forced), name, motionValue2, element);
    this.keyframeResolver?.scheduleResolve();
  }
  onKeyframesResolved(keyframes2, finalKeyframe, options, sync) {
    this.keyframeResolver = void 0;
    const { name, type, velocity, delay: delay2, isHandoff, onUpdate } = options;
    this.resolvedAt = time.now();
    let canAnimateValue = true;
    if (!canAnimate(keyframes2, name, type, velocity)) {
      canAnimateValue = false;
      if (MotionGlobalConfig.instantAnimations || !delay2) {
        onUpdate?.(getFinalKeyframe(keyframes2, options, finalKeyframe));
      }
      keyframes2[0] = keyframes2[keyframes2.length - 1];
      makeAnimationInstant(options);
      options.repeat = 0;
    }
    const startTime = sync ? !this.resolvedAt ? this.createdAt : this.resolvedAt - this.createdAt > MAX_RESOLVE_DELAY ? this.resolvedAt : this.createdAt : void 0;
    const resolvedOptions = {
      startTime,
      finalKeyframe,
      ...options,
      keyframes: keyframes2
    };
    const useWaapi = canAnimateValue && !isHandoff && supportsBrowserAnimation(resolvedOptions);
    const element = resolvedOptions.motionValue?.owner?.current;
    let animation;
    if (useWaapi) {
      try {
        animation = new NativeAnimationExtended({
          ...resolvedOptions,
          element
        });
      } catch {
        animation = new JSAnimation(resolvedOptions);
      }
    } else {
      animation = new JSAnimation(resolvedOptions);
    }
    animation.finished.then(() => {
      this.notifyFinished();
    }).catch(noop);
    if (this.pendingTimeline) {
      this.stopTimeline = animation.attachTimeline(this.pendingTimeline);
      this.pendingTimeline = void 0;
    }
    this._animation = animation;
  }
  get finished() {
    if (!this._animation) {
      return this._finished;
    } else {
      return this.animation.finished;
    }
  }
  then(onResolve, _onReject) {
    return this.finished.finally(onResolve).then(() => {
    });
  }
  get animation() {
    if (!this._animation) {
      this.keyframeResolver?.resume();
      flushKeyframeResolvers();
    }
    return this._animation;
  }
  get duration() {
    return this.animation.duration;
  }
  get iterationDuration() {
    return this.animation.iterationDuration;
  }
  get time() {
    return this.animation.time;
  }
  set time(newTime) {
    this.animation.time = newTime;
  }
  get speed() {
    return this.animation.speed;
  }
  get state() {
    return this.animation.state;
  }
  set speed(newSpeed) {
    this.animation.speed = newSpeed;
  }
  get startTime() {
    return this.animation.startTime;
  }
  attachTimeline(timeline) {
    if (this._animation) {
      this.stopTimeline = this.animation.attachTimeline(timeline);
    } else {
      this.pendingTimeline = timeline;
    }
    return () => this.stop();
  }
  play() {
    this.animation.play();
  }
  pause() {
    this.animation.pause();
  }
  complete() {
    this.animation.complete();
  }
  cancel() {
    if (this._animation) {
      this.animation.cancel();
    }
    this.keyframeResolver?.cancel();
  }
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/GroupAnimation.mjs
var GroupAnimation = class {
  constructor(animations) {
    this.stop = () => this.runAll("stop");
    this.animations = animations.filter(Boolean);
  }
  get finished() {
    return Promise.all(this.animations.map((animation) => animation.finished));
  }
  /**
   * TODO: Filter out cancelled or stopped animations before returning
   */
  getAll(propName) {
    return this.animations[0][propName];
  }
  setAll(propName, newValue) {
    for (let i = 0; i < this.animations.length; i++) {
      this.animations[i][propName] = newValue;
    }
  }
  attachTimeline(timeline) {
    const subscriptions = this.animations.map((animation) => animation.attachTimeline(timeline));
    return () => {
      subscriptions.forEach((cancel, i) => {
        cancel && cancel();
        this.animations[i].stop();
      });
    };
  }
  get time() {
    return this.getAll("time");
  }
  set time(time2) {
    this.setAll("time", time2);
  }
  get speed() {
    return this.getAll("speed");
  }
  set speed(speed) {
    this.setAll("speed", speed);
  }
  get state() {
    return this.getAll("state");
  }
  get startTime() {
    return this.getAll("startTime");
  }
  get duration() {
    return getMax(this.animations, "duration");
  }
  get iterationDuration() {
    return getMax(this.animations, "iterationDuration");
  }
  runAll(methodName) {
    this.animations.forEach((controls) => controls[methodName]());
  }
  play() {
    this.runAll("play");
  }
  pause() {
    this.runAll("pause");
  }
  cancel() {
    this.runAll("cancel");
  }
  complete() {
    this.runAll("complete");
  }
};
function getMax(animations, propName) {
  let max = 0;
  for (let i = 0; i < animations.length; i++) {
    const value = animations[i][propName];
    if (value !== null && value > max) {
      max = value;
    }
  }
  return max;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/NativeAnimationWrapper.mjs
var NativeAnimationWrapper = class extends NativeAnimation {
  constructor(animation) {
    super();
    this.animation = animation;
    animation.onfinish = () => {
      this.finishedTime = this.time;
      this.notifyFinished();
    };
  }
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/utils/calc-child-stagger.mjs
function calcChildStagger(children, child, delayChildren, staggerChildren = 0, staggerDirection = 1) {
  const index = Array.from(children).sort((a, b) => a.sortNodePosition(b)).indexOf(child);
  const numChildren = children.size;
  const maxStaggerDuration = (numChildren - 1) * staggerChildren;
  const delayIsFunction = typeof delayChildren === "function";
  return delayIsFunction ? delayChildren(index, numChildren) : staggerDirection === 1 ? index * staggerChildren : maxStaggerDuration - index * staggerChildren;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/index.mjs
var MAX_VELOCITY_DELTA = 30;
var isFloat = (value) => {
  return !isNaN(parseFloat(value));
};
var collectMotionValues = {
  current: void 0
};
var MotionValue = class {
  /**
   * @param init - The initiating value
   * @param config - Optional configuration options
   *
   * -  `transformer`: A function to transform incoming values with.
   */
  constructor(init, options = {}) {
    this.canTrackVelocity = null;
    this.events = {};
    this.updateAndNotify = (v) => {
      const currentTime = time.now();
      if (this.updatedAt !== currentTime) {
        this.setPrevFrameValue();
      }
      this.prev = this.current;
      this.setCurrent(v);
      if (this.current !== this.prev) {
        this.events.change?.notify(this.current);
        if (this.dependents) {
          for (const dependent of this.dependents) {
            dependent.dirty();
          }
        }
      }
    };
    this.hasAnimated = false;
    this.setCurrent(init);
    this.owner = options.owner;
  }
  setCurrent(current2) {
    this.current = current2;
    this.updatedAt = time.now();
    if (this.canTrackVelocity === null && current2 !== void 0) {
      this.canTrackVelocity = isFloat(this.current);
    }
  }
  setPrevFrameValue(prevFrameValue = this.current) {
    this.prevFrameValue = prevFrameValue;
    this.prevUpdatedAt = this.updatedAt;
  }
  /**
   * Adds a function that will be notified when the `MotionValue` is updated.
   *
   * It returns a function that, when called, will cancel the subscription.
   *
   * When calling `onChange` inside a React component, it should be wrapped with the
   * `useEffect` hook. As it returns an unsubscribe function, this should be returned
   * from the `useEffect` function to ensure you don't add duplicate subscribers..
   *
   * ```jsx
   * export const MyComponent = () => {
   *   const x = useMotionValue(0)
   *   const y = useMotionValue(0)
   *   const opacity = useMotionValue(1)
   *
   *   useEffect(() => {
   *     function updateOpacity() {
   *       const maxXY = Math.max(x.get(), y.get())
   *       const newOpacity = transform(maxXY, [0, 100], [1, 0])
   *       opacity.set(newOpacity)
   *     }
   *
   *     const unsubscribeX = x.on("change", updateOpacity)
   *     const unsubscribeY = y.on("change", updateOpacity)
   *
   *     return () => {
   *       unsubscribeX()
   *       unsubscribeY()
   *     }
   *   }, [])
   *
   *   return <motion.div style={{ x }} />
   * }
   * ```
   *
   * @param subscriber - A function that receives the latest value.
   * @returns A function that, when called, will cancel this subscription.
   *
   * @deprecated
   */
  onChange(subscription) {
    if (true) {
      warnOnce(false, `value.onChange(callback) is deprecated. Switch to value.on("change", callback).`);
    }
    return this.on("change", subscription);
  }
  on(eventName, callback) {
    if (!this.events[eventName]) {
      this.events[eventName] = new SubscriptionManager();
    }
    const unsubscribe = this.events[eventName].add(callback);
    if (eventName === "change") {
      return () => {
        unsubscribe();
        frame.read(() => {
          if (!this.events.change.getSize()) {
            this.stop();
          }
        });
      };
    }
    return unsubscribe;
  }
  clearListeners() {
    for (const eventManagers in this.events) {
      this.events[eventManagers].clear();
    }
  }
  /**
   * Attaches a passive effect to the `MotionValue`.
   */
  attach(passiveEffect, stopPassiveEffect) {
    this.passiveEffect = passiveEffect;
    this.stopPassiveEffect = stopPassiveEffect;
  }
  /**
   * Sets the state of the `MotionValue`.
   *
   * @remarks
   *
   * ```jsx
   * const x = useMotionValue(0)
   * x.set(10)
   * ```
   *
   * @param latest - Latest value to set.
   * @param render - Whether to notify render subscribers. Defaults to `true`
   *
   * @public
   */
  set(v) {
    if (!this.passiveEffect) {
      this.updateAndNotify(v);
    } else {
      this.passiveEffect(v, this.updateAndNotify);
    }
  }
  setWithVelocity(prev, current2, delta) {
    this.set(current2);
    this.prev = void 0;
    this.prevFrameValue = prev;
    this.prevUpdatedAt = this.updatedAt - delta;
  }
  /**
   * Set the state of the `MotionValue`, stopping any active animations,
   * effects, and resets velocity to `0`.
   */
  jump(v, endAnimation = true) {
    this.updateAndNotify(v);
    this.prev = v;
    this.prevUpdatedAt = this.prevFrameValue = void 0;
    endAnimation && this.stop();
    if (this.stopPassiveEffect)
      this.stopPassiveEffect();
  }
  dirty() {
    this.events.change?.notify(this.current);
  }
  addDependent(dependent) {
    if (!this.dependents) {
      this.dependents = /* @__PURE__ */ new Set();
    }
    this.dependents.add(dependent);
  }
  removeDependent(dependent) {
    if (this.dependents) {
      this.dependents.delete(dependent);
    }
  }
  /**
   * Returns the latest state of `MotionValue`
   *
   * @returns - The latest state of `MotionValue`
   *
   * @public
   */
  get() {
    if (collectMotionValues.current) {
      collectMotionValues.current.push(this);
    }
    return this.current;
  }
  /**
   * @public
   */
  getPrevious() {
    return this.prev;
  }
  /**
   * Returns the latest velocity of `MotionValue`
   *
   * @returns - The latest velocity of `MotionValue`. Returns `0` if the state is non-numerical.
   *
   * @public
   */
  getVelocity() {
    const currentTime = time.now();
    if (!this.canTrackVelocity || this.prevFrameValue === void 0 || currentTime - this.updatedAt > MAX_VELOCITY_DELTA) {
      return 0;
    }
    const delta = Math.min(this.updatedAt - this.prevUpdatedAt, MAX_VELOCITY_DELTA);
    return velocityPerSecond(parseFloat(this.current) - parseFloat(this.prevFrameValue), delta);
  }
  /**
   * Registers a new animation to control this `MotionValue`. Only one
   * animation can drive a `MotionValue` at one time.
   *
   * ```jsx
   * value.start()
   * ```
   *
   * @param animation - A function that starts the provided animation
   */
  start(startAnimation) {
    this.stop();
    return new Promise((resolve3) => {
      this.hasAnimated = true;
      this.animation = startAnimation(resolve3);
      if (this.events.animationStart) {
        this.events.animationStart.notify();
      }
    }).then(() => {
      if (this.events.animationComplete) {
        this.events.animationComplete.notify();
      }
      this.clearAnimation();
    });
  }
  /**
   * Stop the currently active animation.
   *
   * @public
   */
  stop() {
    if (this.animation) {
      this.animation.stop();
      if (this.events.animationCancel) {
        this.events.animationCancel.notify();
      }
    }
    this.clearAnimation();
  }
  /**
   * Returns `true` if this value is currently animating.
   *
   * @public
   */
  isAnimating() {
    return !!this.animation;
  }
  clearAnimation() {
    delete this.animation;
  }
  /**
   * Destroy and clean up subscribers to this `MotionValue`.
   *
   * The `MotionValue` hooks like `useMotionValue` and `useTransform` automatically
   * handle the lifecycle of the returned `MotionValue`, so this method is only necessary if you've manually
   * created a `MotionValue` via the `motionValue` function.
   *
   * @public
   */
  destroy() {
    this.dependents?.clear();
    this.events.destroy?.notify();
    this.clearListeners();
    this.stop();
    if (this.stopPassiveEffect) {
      this.stopPassiveEffect();
    }
  }
};
function motionValue(init, options) {
  return new MotionValue(init, options);
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/utils/resolve-transition.mjs
function resolveTransition(transition, parentTransition) {
  if (transition?.inherit && parentTransition) {
    const { inherit: _, ...rest } = transition;
    return { ...parentTransition, ...rest };
  }
  return transition;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/utils/get-value-transition.mjs
function getValueTransition(transition, key) {
  const valueTransition = transition?.[key] ?? transition?.["default"] ?? transition;
  if (valueTransition !== transition) {
    return resolveTransition(valueTransition, transition);
  }
  return valueTransition;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/utils/default-transitions.mjs
var underDampedSpring = {
  type: "spring",
  stiffness: 500,
  damping: 25,
  restSpeed: 10
};
var criticallyDampedSpring = (target) => ({
  type: "spring",
  stiffness: 550,
  damping: target === 0 ? 2 * Math.sqrt(550) : 30,
  restSpeed: 10
});
var keyframesTransition = {
  type: "keyframes",
  duration: 0.8
};
var ease = {
  type: "keyframes",
  ease: [0.25, 0.1, 0.35, 1],
  duration: 0.3
};
var getDefaultTransition = (valueKey, { keyframes: keyframes2 }) => {
  if (keyframes2.length > 2) {
    return keyframesTransition;
  } else if (transformProps.has(valueKey)) {
    return valueKey.startsWith("scale") ? criticallyDampedSpring(keyframes2[1]) : underDampedSpring;
  }
  return ease;
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/utils/is-transition-defined.mjs
var orchestrationKeys = /* @__PURE__ */ new Set([
  "when",
  "delay",
  "delayChildren",
  "staggerChildren",
  "staggerDirection",
  "repeat",
  "repeatType",
  "repeatDelay",
  "from",
  "elapsed"
]);
function isTransitionDefined(transition) {
  for (const key in transition) {
    if (!orchestrationKeys.has(key))
      return true;
  }
  return false;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/interfaces/motion-value.mjs
var animateMotionValue = (name, value, target, transition = {}, element, isHandoff) => (onComplete) => {
  const valueTransition = getValueTransition(transition, name) || {};
  const delay2 = valueTransition.delay || transition.delay || 0;
  let { elapsed = 0 } = transition;
  elapsed = elapsed - secondsToMilliseconds(delay2);
  const options = {
    keyframes: Array.isArray(target) ? target : [null, target],
    ease: "easeOut",
    velocity: value.getVelocity(),
    ...valueTransition,
    delay: -elapsed,
    onUpdate: (v) => {
      value.set(v);
      valueTransition.onUpdate && valueTransition.onUpdate(v);
    },
    onComplete: () => {
      onComplete();
      valueTransition.onComplete && valueTransition.onComplete();
    },
    name,
    motionValue: value,
    element: isHandoff ? void 0 : element
  };
  if (!isTransitionDefined(valueTransition)) {
    Object.assign(options, getDefaultTransition(name, options));
  }
  options.duration && (options.duration = secondsToMilliseconds(options.duration));
  options.repeatDelay && (options.repeatDelay = secondsToMilliseconds(options.repeatDelay));
  if (options.from !== void 0) {
    options.keyframes[0] = options.from;
  }
  let shouldSkip = false;
  if (options.type === false || options.duration === 0 && !options.repeatDelay) {
    makeAnimationInstant(options);
    if (options.delay === 0) {
      shouldSkip = true;
    }
  }
  if (MotionGlobalConfig.instantAnimations || MotionGlobalConfig.skipAnimations || element?.shouldSkipAnimations || valueTransition.skipAnimations) {
    shouldSkip = true;
    makeAnimationInstant(options);
    options.delay = 0;
  }
  options.allowFlatten = !valueTransition.type && !valueTransition.ease;
  if (shouldSkip && !isHandoff && value.get() !== void 0) {
    const finalKeyframe = getFinalKeyframe(options.keyframes, valueTransition);
    if (finalKeyframe !== void 0) {
      frame.update(() => {
        options.onUpdate(finalKeyframe);
        options.onComplete();
      });
      return;
    }
  }
  return valueTransition.isSync ? new JSAnimation(options) : new AsyncMotionValueAnimation(options);
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/utils/css-variables-conversion.mjs
var splitCSSVariableRegex = (
  // eslint-disable-next-line redos-detector/no-unsafe-regex -- false positive, as it can match a lot of words
  /^var\(--(?:([\w-]+)|([\w-]+), ?([a-zA-Z\d ()%#.,-]+))\)/u
);
function parseCSSVariable(current2) {
  const match2 = splitCSSVariableRegex.exec(current2);
  if (!match2)
    return [,];
  const [, token1, token2, fallback] = match2;
  return [`--${token1 ?? token2}`, fallback];
}
var maxDepth = 4;
function getVariableValue(current2, element, depth = 1) {
  invariant(depth <= maxDepth, `Max CSS variable fallback depth detected in property "${current2}". This may indicate a circular fallback dependency.`, "max-css-var-depth");
  const [token, fallback] = parseCSSVariable(current2);
  if (!token)
    return;
  const resolved = window.getComputedStyle(element).getPropertyValue(token);
  if (resolved) {
    const trimmed = resolved.trim();
    return isNumericalString(trimmed) ? parseFloat(trimmed) : trimmed;
  }
  return isCSSVariableToken(fallback) ? getVariableValue(fallback, element, depth + 1) : fallback;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/utils/resolve-variants.mjs
function getValueState(visualElement) {
  const state = [{}, {}];
  visualElement?.values.forEach((value, key) => {
    state[0][key] = value.get();
    state[1][key] = value.getVelocity();
  });
  return state;
}
function resolveVariantFromProps(props, definition, custom, visualElement) {
  if (typeof definition === "function") {
    const [current2, velocity] = getValueState(visualElement);
    definition = definition(custom !== void 0 ? custom : props.custom, current2, velocity);
  }
  if (typeof definition === "string") {
    definition = props.variants && props.variants[definition];
  }
  if (typeof definition === "function") {
    const [current2, velocity] = getValueState(visualElement);
    definition = definition(custom !== void 0 ? custom : props.custom, current2, velocity);
  }
  return definition;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/utils/resolve-dynamic-variants.mjs
function resolveVariant(visualElement, definition, custom) {
  const props = visualElement.getProps();
  return resolveVariantFromProps(props, definition, custom !== void 0 ? custom : props.custom, visualElement);
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/utils/keys-position.mjs
var positionalKeys = /* @__PURE__ */ new Set([
  "width",
  "height",
  "top",
  "left",
  "right",
  "bottom",
  ...transformPropOrder
]);

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/utils/is-keyframes-target.mjs
var isKeyframesTarget = (v) => {
  return Array.isArray(v);
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/utils/setters.mjs
function setMotionValue(visualElement, key, value) {
  if (visualElement.hasValue(key)) {
    visualElement.getValue(key).set(value);
  } else {
    visualElement.addValue(key, motionValue(value));
  }
}
function resolveFinalValueInKeyframes(v) {
  return isKeyframesTarget(v) ? v[v.length - 1] || 0 : v;
}
function setTarget(visualElement, definition) {
  const resolved = resolveVariant(visualElement, definition);
  let { transitionEnd = {}, transition = {}, ...target } = resolved || {};
  target = { ...target, ...transitionEnd };
  for (const key in target) {
    const value = resolveFinalValueInKeyframes(target[key]);
    setMotionValue(visualElement, key, value);
  }
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/utils/is-motion-value.mjs
var isMotionValue = (value) => Boolean(value && value.getVelocity);

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/will-change/is.mjs
function isWillChangeMotionValue(value) {
  return Boolean(isMotionValue(value) && value.add);
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/will-change/add-will-change.mjs
function addValueToWillChange(visualElement, key) {
  const willChange = visualElement.getValue("willChange");
  if (isWillChangeMotionValue(willChange)) {
    return willChange.add(key);
  } else if (!willChange && MotionGlobalConfig.WillChange) {
    const newWillChange = new MotionGlobalConfig.WillChange("auto");
    visualElement.addValue("willChange", newWillChange);
    newWillChange.add(key);
  }
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/dom/utils/camel-to-dash.mjs
function camelToDash(str) {
  return str.replace(/([A-Z])/g, (match2) => `-${match2.toLowerCase()}`);
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/optimized-appear/data-id.mjs
var optimizedAppearDataId = "framerAppearId";
var optimizedAppearDataAttribute = "data-" + camelToDash(optimizedAppearDataId);

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/optimized-appear/get-appear-id.mjs
function getOptimisedAppearId(visualElement) {
  return visualElement.props[optimizedAppearDataAttribute];
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/interfaces/visual-element-target.mjs
var isBrowser = typeof window !== "undefined";
function shouldBlockAnimation({ protectedKeys, needsAnimating }, key) {
  const shouldBlock = protectedKeys.hasOwnProperty(key) && needsAnimating[key] !== true;
  needsAnimating[key] = false;
  return shouldBlock;
}
function animateTarget(visualElement, targetAndTransition, { delay: delay2 = 0, transitionOverride, type } = {}) {
  let { transition, transitionEnd, ...target } = targetAndTransition;
  const defaultTransition = visualElement.getDefaultTransition();
  transition = transition ? resolveTransition(transition, defaultTransition) : defaultTransition;
  const reduceMotion = transition?.reduceMotion;
  const skipAnimations = transition?.skipAnimations;
  if (transitionOverride)
    transition = transitionOverride;
  const animations = [];
  const animationTypeState = type && visualElement.animationState && visualElement.animationState.getState()[type];
  const path = transition?.path;
  if (path) {
    path.animateVisualElement(visualElement, target, transition, delay2, animations);
  }
  for (const key in target) {
    const value = visualElement.getValue(key, visualElement.latestValues[key] ?? null);
    const valueTarget = target[key];
    if (valueTarget === void 0 || animationTypeState && shouldBlockAnimation(animationTypeState, key)) {
      continue;
    }
    const valueTransition = {
      delay: delay2,
      ...getValueTransition(transition || {}, key)
    };
    if (skipAnimations)
      valueTransition.skipAnimations = true;
    const currentValue2 = value.get();
    if (currentValue2 !== void 0 && !value.isAnimating() && !Array.isArray(valueTarget) && valueTarget === currentValue2 && !valueTransition.velocity) {
      frame.update(() => value.set(valueTarget));
      continue;
    }
    let isHandoff = false;
    if (isBrowser && window.MotionHandoffAnimation) {
      const appearId = getOptimisedAppearId(visualElement);
      if (appearId) {
        const startTime = window.MotionHandoffAnimation(appearId, key, frame);
        if (startTime !== null) {
          valueTransition.startTime = startTime;
          isHandoff = true;
        }
      }
    }
    addValueToWillChange(visualElement, key);
    const shouldReduceMotion = reduceMotion ?? visualElement.shouldReduceMotion;
    value.start(animateMotionValue(key, value, valueTarget, shouldReduceMotion && positionalKeys.has(key) ? { type: false } : valueTransition, visualElement, isHandoff));
    const animation = value.animation;
    if (animation) {
      animations.push(animation);
    }
  }
  if (transitionEnd) {
    const applyTransitionEnd = () => frame.update(() => {
      transitionEnd && setTarget(visualElement, transitionEnd);
    });
    if (animations.length) {
      Promise.all(animations).then(applyTransitionEnd);
    } else {
      applyTransitionEnd();
    }
  }
  return animations;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/interfaces/visual-element-variant.mjs
function animateVariant(visualElement, variant, options = {}) {
  const resolved = resolveVariant(visualElement, variant, options.type === "exit" ? visualElement.presenceContext?.custom : void 0);
  let { transition = visualElement.getDefaultTransition() || {} } = resolved || {};
  if (options.transitionOverride) {
    transition = options.transitionOverride;
  }
  const getAnimation = resolved ? () => Promise.all(animateTarget(visualElement, resolved, options)) : () => Promise.resolve();
  const getChildAnimations = visualElement.variantChildren && visualElement.variantChildren.size ? (forwardDelay = 0) => {
    const { delayChildren = 0, staggerChildren, staggerDirection } = transition;
    return animateChildren(visualElement, variant, forwardDelay, delayChildren, staggerChildren, staggerDirection, options);
  } : () => Promise.resolve();
  const { when } = transition;
  if (when) {
    const [first, last] = when === "beforeChildren" ? [getAnimation, getChildAnimations] : [getChildAnimations, getAnimation];
    return first().then(() => last());
  } else {
    return Promise.all([getAnimation(), getChildAnimations(options.delay)]);
  }
}
function animateChildren(visualElement, variant, delay2 = 0, delayChildren = 0, staggerChildren = 0, staggerDirection = 1, options) {
  const animations = [];
  for (const child of visualElement.variantChildren) {
    child.notify("AnimationStart", variant);
    animations.push(animateVariant(child, variant, {
      ...options,
      delay: delay2 + (typeof delayChildren === "function" ? 0 : delayChildren) + calcChildStagger(visualElement.variantChildren, child, delayChildren, staggerChildren, staggerDirection)
    }).then(() => child.notify("AnimationComplete", variant)));
  }
  return Promise.all(animations);
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/interfaces/visual-element.mjs
function animateVisualElement(visualElement, definition, options = {}) {
  visualElement.notify("AnimationStart", definition);
  let animation;
  if (Array.isArray(definition)) {
    const animations = definition.map((variant) => animateVariant(visualElement, variant, options));
    animation = Promise.all(animations);
  } else if (typeof definition === "string") {
    animation = animateVariant(visualElement, definition, options);
  } else {
    const resolvedDefinition = typeof definition === "function" ? resolveVariant(visualElement, definition, options.custom) : definition;
    animation = Promise.all(animateTarget(visualElement, resolvedDefinition, options));
  }
  return animation.then(() => {
    visualElement.notify("AnimationComplete", definition);
  });
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/types/auto.mjs
var auto = {
  test: (v) => v === "auto",
  parse: (v) => v
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/types/test.mjs
var testValueType = (v) => (type) => type.test(v);

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/types/dimensions.mjs
var dimensionValueTypes = [number, px, percent, degrees, vw, vh, auto];
var findDimensionValueType = (v) => dimensionValueTypes.find(testValueType(v));

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/keyframes/utils/is-none.mjs
function isNone(value) {
  if (typeof value === "number") {
    return value === 0;
  } else if (value !== null) {
    return value === "none" || value === "0" || isZeroValueString(value);
  } else {
    return true;
  }
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/types/complex/filter.mjs
var maxDefaults = /* @__PURE__ */ new Set(["brightness", "contrast", "saturate", "opacity"]);
function applyDefaultFilter(v) {
  const [name, value] = v.slice(0, -1).split("(");
  if (name === "drop-shadow")
    return v;
  const [number2] = value.match(floatRegex) || [];
  if (!number2)
    return v;
  const unit = value.replace(number2, "");
  let defaultValue = maxDefaults.has(name) ? 1 : 0;
  if (number2 !== value)
    defaultValue *= 100;
  return name + "(" + defaultValue + unit + ")";
}
var functionRegex = /\b([a-z-]*)\(.*?\)/gu;
var filter = {
  ...complex,
  getAnimatableNone: (v) => {
    const functions = v.match(functionRegex);
    return functions ? functions.map(applyDefaultFilter).join(" ") : v;
  }
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/types/complex/mask.mjs
var mask = {
  ...complex,
  getAnimatableNone: (v) => {
    const parsed = complex.parse(v);
    const transformer = complex.createTransformer(v);
    return transformer(parsed.map((v2) => typeof v2 === "number" ? 0 : typeof v2 === "object" ? { ...v2, alpha: 1 } : v2));
  }
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/types/int.mjs
var int = {
  ...number,
  transform: Math.round
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/types/maps/transform.mjs
var transformValueTypes = {
  rotate: degrees,
  /**
   * Internal channel for `transition.path` orientToPath. Composed onto
   * `rotate` at the transform-build sites so the user's `rotate` is
   * never read or overwritten. Not part of `transformPropOrder`.
   */
  pathRotation: degrees,
  rotateX: degrees,
  rotateY: degrees,
  rotateZ: degrees,
  scale,
  scaleX: scale,
  scaleY: scale,
  scaleZ: scale,
  skew: degrees,
  skewX: degrees,
  skewY: degrees,
  distance: px,
  translateX: px,
  translateY: px,
  translateZ: px,
  x: px,
  y: px,
  z: px,
  perspective: px,
  transformPerspective: px,
  opacity: alpha,
  originX: progressPercentage,
  originY: progressPercentage,
  originZ: px
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/types/maps/number.mjs
var numberValueTypes = {
  // Border props
  borderWidth: px,
  borderTopWidth: px,
  borderRightWidth: px,
  borderBottomWidth: px,
  borderLeftWidth: px,
  borderRadius: px,
  borderTopLeftRadius: px,
  borderTopRightRadius: px,
  borderBottomRightRadius: px,
  borderBottomLeftRadius: px,
  // Positioning props
  width: px,
  maxWidth: px,
  height: px,
  maxHeight: px,
  top: px,
  right: px,
  bottom: px,
  left: px,
  inset: px,
  insetBlock: px,
  insetBlockStart: px,
  insetBlockEnd: px,
  insetInline: px,
  insetInlineStart: px,
  insetInlineEnd: px,
  // Spacing props
  padding: px,
  paddingTop: px,
  paddingRight: px,
  paddingBottom: px,
  paddingLeft: px,
  paddingBlock: px,
  paddingBlockStart: px,
  paddingBlockEnd: px,
  paddingInline: px,
  paddingInlineStart: px,
  paddingInlineEnd: px,
  margin: px,
  marginTop: px,
  marginRight: px,
  marginBottom: px,
  marginLeft: px,
  marginBlock: px,
  marginBlockStart: px,
  marginBlockEnd: px,
  marginInline: px,
  marginInlineStart: px,
  marginInlineEnd: px,
  // Typography
  fontSize: px,
  // Misc
  backgroundPositionX: px,
  backgroundPositionY: px,
  ...transformValueTypes,
  zIndex: int,
  // SVG
  fillOpacity: alpha,
  strokeOpacity: alpha,
  numOctaves: int
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/types/maps/defaults.mjs
var defaultValueTypes = {
  ...numberValueTypes,
  // Color props
  color,
  backgroundColor: color,
  outlineColor: color,
  fill: color,
  stroke: color,
  // Border props
  borderColor: color,
  borderTopColor: color,
  borderRightColor: color,
  borderBottomColor: color,
  borderLeftColor: color,
  filter,
  WebkitFilter: filter,
  mask,
  WebkitMask: mask
};
var getDefaultValueType = (key) => defaultValueTypes[key];

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/types/utils/animatable-none.mjs
var customTypes = /* @__PURE__ */ new Set([filter, mask]);
function getAnimatableNone2(key, value) {
  let defaultValueType = getDefaultValueType(key);
  if (!customTypes.has(defaultValueType))
    defaultValueType = complex;
  return defaultValueType.getAnimatableNone ? defaultValueType.getAnimatableNone(value) : void 0;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/keyframes/utils/make-none-animatable.mjs
var invalidTemplates = /* @__PURE__ */ new Set(["auto", "none", "0"]);
function makeNoneKeyframesAnimatable(unresolvedKeyframes, noneKeyframeIndexes, name) {
  let i = 0;
  let animatableTemplate = void 0;
  while (i < unresolvedKeyframes.length && !animatableTemplate) {
    const keyframe = unresolvedKeyframes[i];
    if (typeof keyframe === "string" && !invalidTemplates.has(keyframe) && analyseComplexValue(keyframe).values.length) {
      animatableTemplate = unresolvedKeyframes[i];
    }
    i++;
  }
  if (animatableTemplate && name) {
    for (const noneIndex of noneKeyframeIndexes) {
      unresolvedKeyframes[noneIndex] = getAnimatableNone2(name, animatableTemplate);
    }
  }
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/keyframes/DOMKeyframesResolver.mjs
var DOMKeyframesResolver = class extends KeyframeResolver {
  constructor(unresolvedKeyframes, onComplete, name, motionValue2, element) {
    super(unresolvedKeyframes, onComplete, name, motionValue2, element, true);
  }
  readKeyframes() {
    const { unresolvedKeyframes, element, name } = this;
    if (!element || !element.current)
      return;
    super.readKeyframes();
    for (let i = 0; i < unresolvedKeyframes.length; i++) {
      let keyframe = unresolvedKeyframes[i];
      if (typeof keyframe === "string") {
        keyframe = keyframe.trim();
        if (isCSSVariableToken(keyframe)) {
          const resolved = getVariableValue(keyframe, element.current);
          if (resolved !== void 0) {
            unresolvedKeyframes[i] = resolved;
          }
          if (i === unresolvedKeyframes.length - 1) {
            this.finalKeyframe = keyframe;
          }
        }
      }
    }
    this.resolveNoneKeyframes();
    if (!positionalKeys.has(name) || unresolvedKeyframes.length !== 2) {
      return;
    }
    const [origin, target] = unresolvedKeyframes;
    const originType = findDimensionValueType(origin);
    const targetType = findDimensionValueType(target);
    const originHasVar = containsCSSVariable(origin);
    const targetHasVar = containsCSSVariable(target);
    if (originHasVar !== targetHasVar && positionalValues[name]) {
      this.needsMeasurement = true;
      return;
    }
    if (originType === targetType)
      return;
    if (isNumOrPxType(originType) && isNumOrPxType(targetType)) {
      for (let i = 0; i < unresolvedKeyframes.length; i++) {
        const value = unresolvedKeyframes[i];
        if (typeof value === "string") {
          unresolvedKeyframes[i] = parseFloat(value);
        }
      }
    } else if (positionalValues[name]) {
      this.needsMeasurement = true;
    }
  }
  resolveNoneKeyframes() {
    const { unresolvedKeyframes, name } = this;
    const noneKeyframeIndexes = [];
    for (let i = 0; i < unresolvedKeyframes.length; i++) {
      if (unresolvedKeyframes[i] === null || isNone(unresolvedKeyframes[i])) {
        noneKeyframeIndexes.push(i);
      }
    }
    if (noneKeyframeIndexes.length) {
      makeNoneKeyframesAnimatable(unresolvedKeyframes, noneKeyframeIndexes, name);
    }
  }
  measureInitialState() {
    const { element, unresolvedKeyframes, name } = this;
    if (!element || !element.current)
      return;
    if (name === "height") {
      this.suspendedScrollY = window.pageYOffset;
    }
    this.measuredOrigin = positionalValues[name](element.measureViewportBox(), window.getComputedStyle(element.current));
    unresolvedKeyframes[0] = this.measuredOrigin;
    const measureKeyframe = unresolvedKeyframes[unresolvedKeyframes.length - 1];
    if (measureKeyframe !== void 0) {
      element.getValue(name, measureKeyframe).jump(measureKeyframe, false);
    }
  }
  measureEndState() {
    const { element, name, unresolvedKeyframes } = this;
    if (!element || !element.current)
      return;
    const value = element.getValue(name);
    value && value.jump(this.measuredOrigin, false);
    const finalKeyframeIndex = unresolvedKeyframes.length - 1;
    const finalKeyframe = unresolvedKeyframes[finalKeyframeIndex];
    unresolvedKeyframes[finalKeyframeIndex] = positionalValues[name](element.measureViewportBox(), window.getComputedStyle(element.current));
    if (finalKeyframe !== null && this.finalKeyframe === void 0) {
      this.finalKeyframe = finalKeyframe;
    }
    if (this.removedTransforms?.length) {
      this.removedTransforms.forEach(([unsetTransformName, unsetTransformValue]) => {
        element.getValue(unsetTransformName).set(unsetTransformValue);
      });
    }
    this.resolveNoneKeyframes();
  }
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/utils/border-radius.mjs
var cornerRadiusProps = [
  "borderTopLeftRadius",
  "borderTopRightRadius",
  "borderBottomRightRadius",
  "borderBottomLeftRadius"
];

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/utils/resolve-elements.mjs
function resolveElements(elementOrSelector, scope, selectorCache) {
  if (elementOrSelector == null) {
    return [];
  }
  if (elementOrSelector instanceof EventTarget) {
    return [elementOrSelector];
  } else if (typeof elementOrSelector === "string") {
    let root = document;
    if (scope) {
      root = scope.current;
    }
    const elements = selectorCache?.[elementOrSelector] ?? root.querySelectorAll(elementOrSelector);
    return elements ? Array.from(elements) : [];
  }
  return Array.from(elementOrSelector).filter((element) => element != null);
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/types/utils/get-as-type.mjs
var getValueAsType = (value, type) => {
  return type && typeof value === "number" ? type.transform(value) : value;
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/utils/is-html-element.mjs
function isHTMLElement(element) {
  return isObject(element) && "offsetHeight" in element && !("ownerSVGElement" in element);
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/frameloop/microtask.mjs
var { schedule: microtask, cancel: cancelMicrotask } = /* @__PURE__ */ createRenderBatcher(queueMicrotask, false);

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/gestures/drag/state/is-active.mjs
var isDragging = {
  x: false,
  y: false
};
function isDragActive() {
  return isDragging.x || isDragging.y;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/gestures/drag/state/set-active.mjs
function setDragLock(axis) {
  if (axis === "x" || axis === "y") {
    if (isDragging[axis]) {
      return null;
    } else {
      isDragging[axis] = true;
      return () => {
        isDragging[axis] = false;
      };
    }
  } else {
    if (isDragging.x || isDragging.y) {
      return null;
    } else {
      isDragging.x = isDragging.y = true;
      return () => {
        isDragging.x = isDragging.y = false;
      };
    }
  }
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/gestures/utils/setup.mjs
function setupGesture(elementOrSelector, options) {
  const elements = resolveElements(elementOrSelector);
  const gestureAbortController = new AbortController();
  const eventOptions = {
    passive: true,
    ...options,
    signal: gestureAbortController.signal
  };
  const cancel = () => gestureAbortController.abort();
  return [elements, eventOptions, cancel];
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/gestures/hover.mjs
function isValidHover(event) {
  return !(event.pointerType === "touch" || isDragActive());
}
function hover(elementOrSelector, onHoverStart, options = {}) {
  const [elements, eventOptions, cancel] = setupGesture(elementOrSelector, options);
  elements.forEach((element) => {
    let isPressed = false;
    let deferredHoverEnd = false;
    let hoverEndCallback;
    const removePointerLeave = () => {
      element.removeEventListener("pointerleave", onPointerLeave);
    };
    const endHover = (event) => {
      if (hoverEndCallback) {
        hoverEndCallback(event);
        hoverEndCallback = void 0;
      }
      removePointerLeave();
    };
    const onPointerUp = (event) => {
      isPressed = false;
      window.removeEventListener("pointerup", onPointerUp);
      window.removeEventListener("pointercancel", onPointerUp);
      if (deferredHoverEnd) {
        deferredHoverEnd = false;
        endHover(event);
      }
    };
    const onPointerDown = () => {
      isPressed = true;
      window.addEventListener("pointerup", onPointerUp, eventOptions);
      window.addEventListener("pointercancel", onPointerUp, eventOptions);
    };
    const onPointerLeave = (leaveEvent) => {
      if (leaveEvent.pointerType === "touch")
        return;
      if (isPressed) {
        deferredHoverEnd = true;
        return;
      }
      endHover(leaveEvent);
    };
    const onPointerEnter = (enterEvent) => {
      if (!isValidHover(enterEvent))
        return;
      deferredHoverEnd = false;
      const onHoverEnd = onHoverStart(element, enterEvent);
      if (typeof onHoverEnd !== "function")
        return;
      hoverEndCallback = onHoverEnd;
      element.addEventListener("pointerleave", onPointerLeave, eventOptions);
    };
    element.addEventListener("pointerenter", onPointerEnter, eventOptions);
    element.addEventListener("pointerdown", onPointerDown, eventOptions);
  });
  return cancel;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/gestures/utils/is-node-or-child.mjs
var isNodeOrChild = (parent, child) => {
  if (!child) {
    return false;
  } else if (parent === child) {
    return true;
  } else {
    return isNodeOrChild(parent, child.parentElement);
  }
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/gestures/utils/is-primary-pointer.mjs
var isPrimaryPointer = (event) => {
  if (event.pointerType === "mouse") {
    return typeof event.button !== "number" || event.button <= 0;
  } else {
    return event.isPrimary !== false;
  }
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/gestures/press/utils/is-keyboard-accessible.mjs
var keyboardAccessibleElements = /* @__PURE__ */ new Set([
  "BUTTON",
  "INPUT",
  "SELECT",
  "TEXTAREA",
  "A"
]);
function isElementKeyboardAccessible(element) {
  return keyboardAccessibleElements.has(element.tagName) || element.isContentEditable === true;
}
var textInputElements = /* @__PURE__ */ new Set(["INPUT", "SELECT", "TEXTAREA"]);
function isElementTextInput(element) {
  return textInputElements.has(element.tagName) || element.isContentEditable === true;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/gestures/press/utils/state.mjs
var isPressing = /* @__PURE__ */ new WeakSet();

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/gestures/press/utils/keyboard.mjs
function filterEvents(callback) {
  return (event) => {
    if (event.key !== "Enter")
      return;
    callback(event);
  };
}
function firePointerEvent(target, type) {
  target.dispatchEvent(new PointerEvent("pointer" + type, { isPrimary: true, bubbles: true }));
}
var enableKeyboardPress = (focusEvent, eventOptions) => {
  const element = focusEvent.currentTarget;
  if (!element)
    return;
  const handleKeydown = filterEvents(() => {
    if (isPressing.has(element))
      return;
    firePointerEvent(element, "down");
    const handleKeyup = filterEvents(() => {
      firePointerEvent(element, "up");
    });
    const handleBlur = () => firePointerEvent(element, "cancel");
    element.addEventListener("keyup", handleKeyup, eventOptions);
    element.addEventListener("blur", handleBlur, eventOptions);
  });
  element.addEventListener("keydown", handleKeydown, eventOptions);
  element.addEventListener("blur", () => element.removeEventListener("keydown", handleKeydown), eventOptions);
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/gestures/press/index.mjs
function isValidPressEvent(event) {
  return isPrimaryPointer(event) && !isDragActive();
}
var claimedPointerDownEvents = /* @__PURE__ */ new WeakSet();
function press(targetOrSelector, onPressStart, options = {}) {
  const [targets, eventOptions, cancelEvents] = setupGesture(targetOrSelector, options);
  const startPress = (startEvent) => {
    const target = startEvent.currentTarget;
    if (!isValidPressEvent(startEvent))
      return;
    if (claimedPointerDownEvents.has(startEvent))
      return;
    isPressing.add(target);
    if (options.stopPropagation) {
      claimedPointerDownEvents.add(startEvent);
    }
    const onPressEnd = onPressStart(target, startEvent);
    const endEventOptions = { ...eventOptions, capture: true };
    const onPointerEnd = (endEvent, success) => {
      window.removeEventListener("pointerup", onPointerUp, endEventOptions);
      window.removeEventListener("pointercancel", onPointerCancel, endEventOptions);
      if (isPressing.has(target)) {
        isPressing.delete(target);
      }
      if (!isValidPressEvent(endEvent)) {
        return;
      }
      if (typeof onPressEnd === "function") {
        onPressEnd(endEvent, { success });
      }
    };
    const onPointerUp = (upEvent) => {
      onPointerEnd(upEvent, target === window || target === document || options.useGlobalTarget || isNodeOrChild(target, upEvent.target));
    };
    const onPointerCancel = (cancelEvent) => {
      onPointerEnd(cancelEvent, false);
    };
    window.addEventListener("pointerup", onPointerUp, endEventOptions);
    window.addEventListener("pointercancel", onPointerCancel, endEventOptions);
  };
  targets.forEach((target) => {
    const pointerDownTarget = options.useGlobalTarget ? window : target;
    pointerDownTarget.addEventListener("pointerdown", startPress, eventOptions);
    if (isHTMLElement(target)) {
      target.addEventListener("focus", (event) => enableKeyboardPress(event, eventOptions));
      if (!isElementKeyboardAccessible(target) && !target.hasAttribute("tabindex")) {
        target.tabIndex = 0;
      }
    }
  });
  return cancelEvents;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/utils/is-svg-element.mjs
function isSVGElement(element) {
  return isObject(element) && "ownerSVGElement" in element;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/resize/handle-element.mjs
var resizeHandlers = /* @__PURE__ */ new WeakMap();
var observer;
var getSize = (borderBoxAxis, svgAxis, htmlAxis) => (target, borderBoxSize) => {
  if (borderBoxSize && borderBoxSize[0]) {
    return borderBoxSize[0][borderBoxAxis + "Size"];
  } else if (isSVGElement(target) && "getBBox" in target) {
    return target.getBBox()[svgAxis];
  } else {
    return target[htmlAxis];
  }
};
var getWidth = /* @__PURE__ */ getSize("inline", "width", "offsetWidth");
var getHeight = /* @__PURE__ */ getSize("block", "height", "offsetHeight");
function notifyTarget({ target, borderBoxSize }) {
  resizeHandlers.get(target)?.forEach((handler) => {
    handler(target, {
      get width() {
        return getWidth(target, borderBoxSize);
      },
      get height() {
        return getHeight(target, borderBoxSize);
      }
    });
  });
}
function notifyAll(entries) {
  entries.forEach(notifyTarget);
}
function createResizeObserver() {
  if (typeof ResizeObserver === "undefined")
    return;
  observer = new ResizeObserver(notifyAll);
}
function resizeElement(target, handler) {
  if (!observer)
    createResizeObserver();
  const elements = resolveElements(target);
  elements.forEach((element) => {
    let elementHandlers = resizeHandlers.get(element);
    if (!elementHandlers) {
      elementHandlers = /* @__PURE__ */ new Set();
      resizeHandlers.set(element, elementHandlers);
    }
    elementHandlers.add(handler);
    observer?.observe(element);
  });
  return () => {
    elements.forEach((element) => {
      const elementHandlers = resizeHandlers.get(element);
      elementHandlers?.delete(handler);
      if (!elementHandlers?.size) {
        observer?.unobserve(element);
      }
    });
  };
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/resize/handle-window.mjs
var windowCallbacks = /* @__PURE__ */ new Set();
var windowResizeHandler;
function createWindowResizeHandler() {
  windowResizeHandler = () => {
    const info = {
      get width() {
        return window.innerWidth;
      },
      get height() {
        return window.innerHeight;
      }
    };
    windowCallbacks.forEach((callback) => callback(info));
  };
  window.addEventListener("resize", windowResizeHandler);
}
function resizeWindow(callback) {
  windowCallbacks.add(callback);
  if (!windowResizeHandler)
    createWindowResizeHandler();
  return () => {
    windowCallbacks.delete(callback);
    if (!windowCallbacks.size && typeof windowResizeHandler === "function") {
      window.removeEventListener("resize", windowResizeHandler);
      windowResizeHandler = void 0;
    }
  };
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/resize/index.mjs
function resize(a, b) {
  return typeof a === "function" ? resizeWindow(a) : resizeElement(a, b);
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/scroll/observe.mjs
function observeTimeline(update, timeline) {
  let prevProgress;
  const onFrame = () => {
    const { currentTime } = timeline;
    const percentage = currentTime === null ? 0 : currentTime.value;
    const progress2 = percentage / 100;
    if (prevProgress !== progress2) {
      update(progress2);
    }
    prevProgress = progress2;
  };
  frame.preUpdate(onFrame, true);
  return () => cancelFrame(onFrame);
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/stats/buffer.mjs
var statsBuffer = {
  value: null,
  addProjectionMetrics: null
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/utils/is-svg-svg-element.mjs
function isSVGSVGElement(element) {
  return isSVGElement(element) && element.tagName === "svg";
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/utils/stagger.mjs
function getOriginIndex(from, total) {
  if (from === "first") {
    return 0;
  } else {
    const lastIndex = total - 1;
    return from === "last" ? lastIndex : lastIndex / 2;
  }
}
function stagger(duration = 0.1, { startDelay = 0, from = 0, ease: ease3 } = {}) {
  return (i, total) => {
    const fromIndex = typeof from === "number" ? from : getOriginIndex(from, total);
    const distance2 = Math.abs(fromIndex - i);
    let delay2 = duration * distance2;
    if (ease3) {
      const maxDelay = total * duration;
      const easingFunction = easingDefinitionToFunction(ease3);
      delay2 = easingFunction(delay2 / maxDelay) * maxDelay;
    }
    return startDelay + delay2;
  };
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/subscribe-value.mjs
function subscribeValue(inputValues, outputValue, getLatest) {
  const update = () => outputValue.set(getLatest());
  const scheduleUpdate = () => frame.preRender(update, false, true);
  const subscriptions = inputValues.map((v) => v.on("change", scheduleUpdate));
  outputValue.on("destroy", () => {
    subscriptions.forEach((unsubscribe) => unsubscribe());
    cancelFrame(update);
  });
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/transform-value.mjs
function transformValue(transform) {
  const collectedValues = [];
  collectMotionValues.current = collectedValues;
  const initialValue = transform();
  collectMotionValues.current = void 0;
  const value = motionValue(initialValue);
  subscribeValue(collectedValues, value, transform);
  return value;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/types/utils/find.mjs
var valueTypes = [...dimensionValueTypes, color, complex];
var findValueType = (v) => valueTypes.find(testValueType(v));

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/view/utils/assign-names.mjs
var nameCount = 0;
var generatedName = () => `motion-view-${nameCount++}`;
var isGeneratedName = (name) => name.startsWith("motion-view-");
function tagClass(element, className, classed) {
  if (!className)
    return;
  element.style?.setProperty("view-transition-class", className);
  classed.push(element);
}
function applyGroup(element, name, group, grouped, clipChildren) {
  if (!group)
    return;
  element.style?.setProperty("view-transition-group", group);
  grouped.push(element);
  if (group !== "none" && clipChildren) {
    const style2 = getComputedStyle(element);
    if (style2.overflowX !== "visible" || style2.overflowY !== "visible") {
      clipChildren.add(name);
    }
  }
}
function assignViewTransitionNames(definition, registry2, assigned, forcedNames, className, classed = [], group, grouped = [], clipChildren) {
  const elements = resolveElements(definition);
  if (forcedNames) {
    return elements.map((element, i) => {
      const existing = registry2.get(element);
      if (existing)
        return existing;
      const name = forcedNames[i] ?? generatedName();
      element.style?.setProperty("view-transition-name", name);
      assigned.push(element);
      registry2.set(element, name);
      tagClass(element, className, classed);
      applyGroup(element, name, group, grouped, clipChildren);
      return name;
    });
  }
  const currentNames = elements.map((element) => registry2.has(element) ? void 0 : getComputedStyle(element).getPropertyValue("view-transition-name"));
  return elements.map((element, i) => {
    const existing = registry2.get(element);
    if (existing)
      return existing;
    const current2 = currentNames[i];
    let name;
    if (current2 && current2 !== "none" && current2 !== "auto" && current2 !== "match-element" && !isGeneratedName(current2)) {
      name = current2;
    } else {
      name = generatedName();
      element.style?.setProperty("view-transition-name", name);
      assigned.push(element);
    }
    registry2.set(element, name);
    tagClass(element, className, classed);
    applyGroup(element, name, group, grouped, clipChildren);
    return name;
  });
}
function releaseViewTransitionNames(assigned, classed = [], grouped = []) {
  for (const element of assigned) {
    element.style?.removeProperty("view-transition-name");
  }
  for (const element of classed) {
    element.style?.removeProperty("view-transition-class");
  }
  for (const element of grouped) {
    element.style?.removeProperty("view-transition-group");
  }
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/view/utils/choose-layer-type.mjs
function chooseLayerType(valueName) {
  if (valueName === "layout")
    return "group";
  if (valueName === "enter" || valueName === "new")
    return "new";
  return "old";
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/view/utils/css.mjs
var pendingRules = {};
var style = null;
var css = {
  set: (selector2, values) => {
    pendingRules[selector2] = values;
  },
  commit: () => {
    if (!style) {
      style = document.createElement("style");
      style.id = "motion-view";
    }
    let cssText = "";
    for (const selector2 in pendingRules) {
      const rule = pendingRules[selector2];
      cssText += `${selector2} {
`;
      for (const [property, value] of Object.entries(rule)) {
        cssText += `  ${property}: ${value};
`;
      }
      cssText += "}\n";
    }
    style.textContent = cssText;
    document.head.appendChild(style);
    pendingRules = {};
  },
  remove: () => {
    if (style && style.parentElement) {
      style.parentElement.removeChild(style);
    }
  }
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/view/utils/get-layer-info.mjs
function getViewAnimationLayerInfo(pseudoElement) {
  const match2 = pseudoElement.match(
    // `group-children` (nested transitions) before `group` so it wins.
    /::view-transition-(old|new|group-children|group|image-pair)\((.*?)\)/
  );
  if (!match2)
    return null;
  return { layer: match2[2], type: match2[1] };
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/view/utils/get-view-animations.mjs
function getViewAnimations() {
  return document.getAnimations().filter((animation) => {
    const { effect } = animation;
    return !!effect && effect.target === document.documentElement && effect.pseudoElement?.startsWith("::view-transition");
  });
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/view/utils/has-target.mjs
function hasTarget(target, targets) {
  return targets.has(target) && Object.keys(targets.get(target)).length > 0;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/view/start.mjs
var definitionNames = ["layout", "enter", "exit", "new", "old"];
var isSquareRadius = (radius) => radius.split(" ").every((value) => parseFloat(value) === 0);
var typeBuckets = {
  group: ["layout"],
  new: ["new", "enter"],
  old: ["old", "exit"]
};
var ORIGIN_DEFAULTS = {
  new: { opacity: 0, scale: 0.85 },
  old: { opacity: 1, scale: 1 }
};
var ASPECT_TOLERANCE = 0.2;
function startViewAnimation(builder) {
  const { update, targets, resolveDefs, cropOverride, pairs, classNames, flatGroups, options: defaultOptions } = builder;
  if (!document.startViewTransition) {
    return (async () => {
      await update();
      return new GroupAnimation([]);
    })();
  }
  const nameRegistry = /* @__PURE__ */ new Map();
  const assigned = [];
  const classed = [];
  const grouped = [];
  const clipChildren = /* @__PURE__ */ new Set();
  const layerTargets = /* @__PURE__ */ new Map();
  const croppedNames = /* @__PURE__ */ new Set();
  const cropForName = /* @__PURE__ */ new Map();
  const layerStagger = /* @__PURE__ */ new Map();
  const pairNames = /* @__PURE__ */ new Map();
  const pairFrom = /* @__PURE__ */ new Map();
  const resolveLayers = (phase) => {
    targets.forEach((target, definition) => {
      const className = classNames.get(definition);
      const group = definition === "root" || !resolveDefs.has(definition) ? void 0 : flatGroups.has(definition) ? "none" : "contain";
      let names;
      if (definition === "root" || !resolveDefs.has(definition)) {
        names = [definition];
      } else if (pairs.has(definition)) {
        if (phase === "old") {
          pairFrom.set(definition, resolveElements(definition));
          names = assignViewTransitionNames(definition, nameRegistry, assigned, void 0, className, classed, group, grouped, clipChildren);
          pairNames.set(definition, names);
        } else {
          for (const el of pairFrom.get(definition) ?? []) {
            el.style?.removeProperty("view-transition-name");
            nameRegistry.delete(el);
          }
          names = assignViewTransitionNames(pairs.get(definition), nameRegistry, assigned, pairNames.get(definition), className, classed, group, grouped, clipChildren);
        }
      } else {
        names = assignViewTransitionNames(definition, nameRegistry, assigned, void 0, className, classed, group, grouped, clipChildren);
      }
      const override = cropOverride.get(definition);
      names.forEach((name, index) => {
        const existing = layerTargets.get(name);
        layerTargets.set(name, existing && existing !== target ? { ...existing, ...target } : target);
        if (override !== void 0)
          cropForName.set(name, override);
        const stagger2 = layerStagger.get(name) ?? {};
        stagger2[phase] = [index, names.length];
        layerStagger.set(name, stagger2);
      });
    });
  };
  const staggerPosition = (name, type) => {
    const stagger2 = layerStagger.get(name);
    const position = type === "old" ? stagger2?.old : type === "new" ? stagger2?.new : (
      // group / group-children / image-pair persist across both.
      stagger2?.new ?? stagger2?.old
    );
    return position ?? [-1, 1];
  };
  const resolveLayerTransition = (target, type, transitionName, index, total) => {
    const transition2 = mergeTransition(getValueTransition(defaultOptions, transitionName), getValueTransition(layerOptions(target, type) ?? {}, transitionName));
    if (typeof transition2.delay === "function") {
      transition2.delay = transition2.delay(index, total);
    }
    return transition2;
  };
  const resolveGroupTiming = (name) => {
    const [index, total] = staggerPosition(name, "group");
    const transition2 = resolveLayerTransition(layerTargets.get(name), "group", "layout", index === -1 ? 0 : index, total);
    transition2.duration && (transition2.duration = secondsToMilliseconds(transition2.duration));
    const { delay: delay2 = 0, duration, ease: ease3 } = applyGeneratorOptions(transition2);
    return { delay: secondsToMilliseconds(delay2), duration, ease: ease3 };
  };
  const cropMeasurements = /* @__PURE__ */ new Map();
  const measureLayers = (phase) => nameRegistry.forEach((name, element) => {
    const el = element;
    const rect2 = el.getBoundingClientRect?.();
    if (rect2 && rect2.height) {
      const style2 = getComputedStyle(el);
      const radii = {};
      for (const corner of cornerRadiusProps) {
        radii[corner] = style2[corner];
      }
      const entry = cropMeasurements.get(name) ?? {};
      entry[phase] = { width: rect2.width, height: rect2.height, radii };
      cropMeasurements.set(name, entry);
    }
  });
  const finalizeCrop = () => {
    croppedNames.clear();
    for (const name of layerStagger.keys()) {
      if (name === "root")
        continue;
      if (cropForName.get(name) ?? aspectChanged(name)) {
        croppedNames.add(name);
      }
    }
  };
  const aspectChanged = (name) => {
    const box = cropMeasurements.get(name);
    if (!box?.old || !box?.new || !box.old.height || !box.new.height) {
      return false;
    }
    return Math.abs(box.old.width / box.old.height - box.new.width / box.new.height) > ASPECT_TOLERANCE;
  };
  const commitViewCSS = () => {
    if (!hasTarget("root", targets)) {
      css.set(":root", { "view-transition-name": "none" });
    }
    css.set("::view-transition-group(*), ::view-transition-old(*), ::view-transition-new(*)", { "animation-timing-function": "linear !important" });
    croppedNames.forEach((name) => {
      css.set(`::view-transition-group(${name})`, { overflow: "clip" });
      css.set(`::view-transition-old(${name}), ::view-transition-new(${name})`, { width: "100%", height: "100%", "object-fit": "cover" });
    });
    clipChildren.forEach((name) => {
      css.set(`::view-transition-group-children(${name})`, {
        overflow: "clip"
      });
    });
    css.commit();
  };
  const cleanup = () => {
    releaseViewTransitionNames(assigned, classed, grouped);
    css.remove();
  };
  const callback = async () => {
    await update();
    resolveLayers("new");
    measureLayers("new");
    finalizeCrop();
    commitViewCSS();
  };
  let transition;
  try {
    resolveLayers("old");
    measureLayers("old");
    commitViewCSS();
    transition = document.startViewTransition(callback);
  } catch (error) {
    cleanup();
    return Promise.reject(error);
  }
  transition.finished.finally(cleanup);
  return new Promise((resolve3, reject) => {
    transition.ready.then(() => {
      const generatedViewAnimations = getViewAnimations();
      const animations = [];
      const explicitlyAnimated = /* @__PURE__ */ new Set();
      const opacityAnimated = /* @__PURE__ */ new Set();
      layerTargets.forEach((target, name) => {
        const stagger2 = layerStagger.get(name);
        const enterApplies = !!stagger2?.new && !stagger2?.old;
        const exitApplies = !!stagger2?.old && !stagger2?.new;
        for (const key of definitionNames) {
          if (!target[key])
            continue;
          if (key === "enter" && !enterApplies)
            continue;
          if (key === "exit" && !exitApplies)
            continue;
          const type = chooseLayerType(key);
          const [index, total] = staggerPosition(name, type);
          if (index === -1)
            continue;
          const { keyframes: keyframes2, options } = target[key];
          for (let [valueName, valueKeyframes] of Object.entries(keyframes2)) {
            if (valueKeyframes == null)
              continue;
            if (valueName === "x" || valueName === "y") {
              warnOnce(false, `animateView() animates view-transition layers with CSS properties; the "${valueName}" shorthand has no effect - use transform, e.g. { transform: "translateX(40px)" }.`);
              continue;
            }
            if (key === "new" && enterApplies && target.enter?.keyframes[valueName] != null) {
              continue;
            }
            if (key === "old" && exitApplies && target.exit?.keyframes[valueName] != null) {
              continue;
            }
            const valueOptions = mergeTransition(getValueTransition(defaultOptions, valueName), getValueTransition(options, valueName));
            if (!Array.isArray(valueKeyframes)) {
              const exitValue = key === "enter" ? target.exit?.keyframes[valueName] : void 0;
              const allowDefault = valueName === "opacity" || (type === "new" ? enterApplies : exitApplies);
              const from = exitValue != null ? Array.isArray(exitValue) ? exitValue[exitValue.length - 1] : exitValue : allowDefault ? ORIGIN_DEFAULTS[type]?.[valueName] : void 0;
              if (from !== void 0) {
                valueKeyframes = [from, valueKeyframes];
              }
            }
            if (typeof valueOptions.delay === "function") {
              valueOptions.delay = valueOptions.delay(index, total);
            }
            valueOptions.duration && (valueOptions.duration = secondsToMilliseconds(valueOptions.duration));
            valueOptions.delay && (valueOptions.delay = secondsToMilliseconds(valueOptions.delay));
            animations.push(new NativeAnimation({
              ...valueOptions,
              element: document.documentElement,
              name: valueName,
              pseudoElement: `::view-transition-${type}(${name})`,
              keyframes: valueKeyframes
            }));
            explicitlyAnimated.add(`${name}:${type}`);
            if (valueName === "opacity") {
              opacityAnimated.add(`${name}:${type}`);
            }
          }
        }
      });
      for (const animation of generatedViewAnimations) {
        if (animation.playState === "finished")
          continue;
        const { effect } = animation;
        if (!effect || !(effect instanceof KeyframeEffect))
          continue;
        const { pseudoElement } = effect;
        if (!pseudoElement)
          continue;
        const name = getViewAnimationLayerInfo(pseudoElement);
        if (!name)
          continue;
        const targetDefinition = layerTargets.get(name.layer);
        if (explicitlyAnimated.has(`${name.layer}:${name.type}`)) {
          const isCrossfade = opacityAnimated.has(`${name.layer}:new`) && opacityAnimated.has(`${name.layer}:old`);
          if (isCrossfade && effect.getKeyframes().some((keyframe) => keyframe.mixBlendMode)) {
            animations.push(new NativeAnimationWrapper(animation));
          } else {
            animation.cancel();
          }
          continue;
        }
        const opposite = name.type === "old" ? "new" : name.type === "new" ? "old" : void 0;
        if (opposite && explicitlyAnimated.has(`${name.layer}:${opposite}`) && !opacityAnimated.has(`${name.layer}:${opposite}`)) {
          animation.cancel();
          continue;
        }
        const stagger2 = layerStagger.get(name.layer);
        const isMorphCrossfade = (name.type === "old" || name.type === "new") && !!stagger2?.old && !!stagger2?.new;
        let timing;
        if (name.type.startsWith("group")) {
          const { delay: delay2, duration, ease: ease3 } = resolveGroupTiming(name.layer);
          timing = {
            delay: delay2,
            duration,
            easing: mapEasingToNativeEasing(ease3, duration)
          };
        } else {
          const timingType = isMorphCrossfade ? "group" : name.type;
          const [index, total] = staggerPosition(name.layer, timingType);
          const transitionName = timingType === "group" ? "layout" : "";
          let animationTransition = resolveLayerTransition(targetDefinition, timingType, transitionName, index === -1 ? 0 : index, total);
          const visualDuration = animationTransition.visualDuration;
          animationTransition.duration && (animationTransition.duration = secondsToMilliseconds(animationTransition.duration));
          animationTransition = applyGeneratorOptions(animationTransition);
          timing = {
            delay: secondsToMilliseconds(animationTransition.delay ?? 0),
            duration: isMorphCrossfade && visualDuration !== void 0 ? secondsToMilliseconds(visualDuration) : animationTransition.duration,
            easing: isMorphCrossfade ? "linear" : mapEasingToNativeEasing(animationTransition.ease, animationTransition.duration)
          };
        }
        effect.updateTiming(timing);
        animations.push(new NativeAnimationWrapper(animation));
      }
      cropMeasurements.forEach((entry, name) => {
        if (!croppedNames.has(name))
          return;
        const { delay: delay2, duration, ease: ease3 } = resolveGroupTiming(name);
        for (const corner of cornerRadiusProps) {
          const from = entry.old?.radii[corner] || entry.new?.radii[corner] || "0px";
          const to2 = entry.new?.radii[corner] || entry.old?.radii[corner] || "0px";
          if (isSquareRadius(from) && isSquareRadius(to2))
            continue;
          animations.push(new NativeAnimation({
            element: document.documentElement,
            name: corner,
            pseudoElement: `::view-transition-group(${name})`,
            keyframes: [from, to2],
            delay: delay2,
            duration,
            ease: ease3
          }));
        }
      });
      resolve3(new GroupAnimation(animations));
    }).catch(() => (
      /**
       * `ready` rejects when the transition is skipped - no visual
       * change, or superseded by an interrupting transition. The DOM
       * update still applied, so settle with no animations rather than
       * surfacing it as an error to an awaiting caller. A genuine
       * failure in `update()` rejects `updateCallbackDone` (already
       * settled by now), so propagate that instead.
       */
      transition.updateCallbackDone.then(() => resolve3(new GroupAnimation([])), reject)
    ));
  });
}
function layerOptions(target, type) {
  for (const bucket of typeBuckets[type] ?? []) {
    const options = target?.[bucket]?.options;
    if (options)
      return options;
  }
}
function mergeTransition(base, override) {
  const merged = { ...base, ...override };
  if (override.duration !== void 0) {
    if (override.visualDuration === void 0)
      delete merged.visualDuration;
    if (override.type === void 0)
      delete merged.type;
  }
  return merged;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/view/queue.mjs
var builders = [];
var current = null;
function next() {
  current = null;
  const [nextBuilder] = builders;
  if (nextBuilder)
    start(nextBuilder);
}
function start(builder) {
  removeItem(builders, builder);
  current = builder;
  startViewAnimation(builder).then((animation) => {
    builder.notifyReady(animation);
    return animation.finished;
  }).catch((error) => builder.notifyReject(error)).finally(next);
}
function processQueue() {
  for (let i = builders.length - 1; i >= 0; i--) {
    const builder = builders[i];
    const { interrupt } = builder.options;
    if (interrupt === "immediate") {
      const batchedUpdates = builders.slice(0, i + 1).map((b) => b.update);
      const remaining = builders.slice(i + 1);
      builder.update = () => {
        batchedUpdates.forEach((update) => update());
      };
      builders = [builder, ...remaining];
      break;
    }
  }
  if (!current || builders[0]?.options.interrupt === "immediate") {
    next();
  }
}
function addToQueue(builder) {
  builders.push(builder);
  microtask.render(processQueue);
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/view/index.mjs
var ViewTransitionBuilder = class {
  constructor(update, options = {}) {
    this.currentSubject = "root";
    this.targets = /* @__PURE__ */ new Map();
    this.resolveDefs = /* @__PURE__ */ new Set();
    this.cropOverride = /* @__PURE__ */ new Map();
    this.pairs = /* @__PURE__ */ new Map();
    this.classNames = /* @__PURE__ */ new Map();
    this.flatGroups = /* @__PURE__ */ new Set();
    this.notifyReady = noop;
    this.notifyReject = noop;
    this.readyPromise = new Promise((resolve3, reject) => {
      this.notifyReady = resolve3;
      this.notifyReject = reject;
    });
    this.update = update;
    this.options = {
      interrupt: "wait",
      ...options
    };
    this.readyPromise.catch(noop);
    addToQueue(this);
  }
  /**
   * Target elements resolved from a selector or Element, each assigned a
   * `view-transition-name` automatically.
   *
   * Passing a second target pairs them: the first is resolved in the old
   * snapshot and the second in the new, sharing one name so two *different*
   * elements morph into each other (e.g. `.add(card, ".modal")`). Symmetric -
   * pass them the other way round to morph back.
   */
  add(subject, newSubject) {
    this.currentSubject = subject;
    this.resolveDefs.add(subject);
    if (newSubject !== void 0)
      this.pairs.set(subject, newSubject);
    if (!this.targets.has(subject))
      this.targets.set(subject, {});
    return this;
  }
  /**
   * Control this subject's crop (clip + `object-fit: cover` + animated
   * corners). By default a subject auto-crops only when it actually morphs -
   * present in both snapshots (a survivor, or an `.add(a, b)` pair). A
   * fade-only enter/exit has no second box to crop against, so it's left to
   * the browser default; in particular the `overflow: clip` a crop adds would
   * otherwise clip a mis-sized enter/exit layer to nothing.
   *
   * `.crop(false)` forces the crop off (e.g. a text morph, where
   * `object-fit: cover` clips glyphs as the box grows); `.crop(true)` forces
   * it on for a non-morph the default wouldn't otherwise crop.
   */
  crop(enabled = true) {
    this.cropOverride.set(this.currentSubject, enabled);
    return this;
  }
  /**
   * By default a subject's layer nests under its nearest DOM-ancestor layer
   * (`view-transition-group: contain`), so the ancestor's clip/transform/opacity
   * apply to it through the transition - mirroring how the DOM actually paints,
   * and letting a wrapper crop its child for the whole morph rather than only
   * once the live DOM takes back over. (Needs a browser that supports nested
   * view-transition groups; elsewhere it degrades to the flat default.)
   *
   * Call `.group(false)` to opt out: the layer stays flat and top-level, so it
   * animates independently and escapes an ancestor's clip - e.g. an element
   * that should lift out of a card and fly across, which nesting would clip.
   */
  group(enabled = true) {
    enabled ? this.flatGroups.delete(this.currentSubject) : this.flatGroups.add(this.currentSubject);
    return this;
  }
  /**
   * Tag this subject's generated layers with a `view-transition-class`, so
   * they can be targeted from CSS - `::view-transition-group(.name)`,
   * `::view-transition-old/new(.name)`, `::view-transition-image-pair(.name)`
   * - without the opaque generated `view-transition-name`. Because `.add()`
   * can match many elements, a shared class targets them all at once (and,
   * for a pair, both ends). The escape hatch for z-index / custom keyframes
   * on a morph layer.
   */
  class(name) {
    this.classNames.set(this.currentSubject, name);
    return this;
  }
  /**
   * Set the transition for this subject's morph. The morph is enabled
   * automatically by `.add()`; this just customises its timing (duration,
   * easing, a `delay`/`stagger`, …). On the implicit `root` subject it also
   * opts the page into the transition (the root crossfade).
   */
  layout(options = {}) {
    this.updateTarget("layout", {}, options);
    return this;
  }
  enter(keyframes2, options) {
    this.updateTarget("enter", keyframes2, options);
    return this;
  }
  exit(keyframes2, options) {
    this.updateTarget("exit", keyframes2, options);
    return this;
  }
  /**
   * Animate the new view directly, whether the element is appearing or
   * persisting (unlike `.enter()`, which only fires for a pure newcomer).
   * Pair with `.old()` for a crossfade or slide-through.
   */
  new(keyframes2, options) {
    this.updateTarget("new", keyframes2, options);
    return this;
  }
  /**
   * Animate the old view directly, whether the element is leaving or
   * persisting (unlike `.exit()`, which only fires for a pure leaver).
   */
  old(keyframes2, options) {
    this.updateTarget("old", keyframes2, options);
    return this;
  }
  updateTarget(target, keyframes2, options = {}) {
    const { currentSubject, targets } = this;
    if (!targets.has(currentSubject)) {
      targets.set(currentSubject, {});
    }
    const targetData = targets.get(currentSubject);
    targetData[target] = { keyframes: keyframes2, options };
  }
  then(resolve3, reject) {
    return this.readyPromise.then(resolve3, reject);
  }
};
function animateView(update, options = {}) {
  return new ViewTransitionBuilder(update, options);
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/projection/geometry/models.mjs
var createAxisDelta = () => ({
  translate: 0,
  scale: 1,
  origin: 0,
  originPoint: 0
});
var createDelta = () => ({
  x: createAxisDelta(),
  y: createAxisDelta()
});
var createAxis = () => ({ min: 0, max: 0 });
var createBox = () => ({
  x: createAxis(),
  y: createAxis()
});

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/store.mjs
var visualElementStore = /* @__PURE__ */ new WeakMap();

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/utils/is-animation-controls.mjs
function isAnimationControls(v) {
  return v !== null && typeof v === "object" && typeof v.start === "function";
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/utils/is-variant-label.mjs
function isVariantLabel(v) {
  return typeof v === "string" || Array.isArray(v);
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/utils/variant-props.mjs
var variantPriorityOrder = [
  "animate",
  "whileInView",
  "whileFocus",
  "whileHover",
  "whileTap",
  "whileDrag",
  "exit"
];
var variantProps = ["initial", ...variantPriorityOrder];

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/utils/is-controlling-variants.mjs
function isControllingVariants(props) {
  return isAnimationControls(props.animate) || variantProps.some((name) => isVariantLabel(props[name]));
}
function isVariantNode(props) {
  return Boolean(isControllingVariants(props) || props.variants);
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/utils/motion-values.mjs
function updateMotionValuesFromProps(element, next2, prev) {
  for (const key in next2) {
    const nextValue = next2[key];
    const prevValue = prev[key];
    if (isMotionValue(nextValue)) {
      element.addValue(key, nextValue);
    } else if (isMotionValue(prevValue)) {
      element.addValue(key, motionValue(nextValue, { owner: element }));
    } else if (prevValue !== nextValue) {
      if (element.hasValue(key)) {
        const existingValue = element.getValue(key);
        if (existingValue.liveStyle === true) {
          existingValue.jump(nextValue);
        } else if (!existingValue.hasAnimated) {
          existingValue.set(nextValue);
        }
      } else {
        const latestValue = element.getStaticValue(key);
        element.addValue(key, motionValue(latestValue !== void 0 ? latestValue : nextValue, { owner: element }));
      }
    }
  }
  for (const key in prev) {
    if (next2[key] === void 0)
      element.removeValue(key);
  }
  return next2;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/utils/reduced-motion/state.mjs
var prefersReducedMotion = { current: null };
var hasReducedMotionListener = { current: false };

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/utils/reduced-motion/index.mjs
var isBrowser2 = typeof window !== "undefined";
function initPrefersReducedMotion() {
  hasReducedMotionListener.current = true;
  if (!isBrowser2)
    return;
  if (window.matchMedia) {
    const motionMediaQuery = window.matchMedia("(prefers-reduced-motion)");
    const setReducedMotionPreferences = () => prefersReducedMotion.current = motionMediaQuery.matches;
    motionMediaQuery.addEventListener("change", setReducedMotionPreferences);
    setReducedMotionPreferences();
  } else {
    prefersReducedMotion.current = false;
  }
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/VisualElement.mjs
var propEventHandlers = [
  "AnimationStart",
  "AnimationComplete",
  "Update",
  "BeforeLayoutMeasure",
  "LayoutMeasure",
  "LayoutAnimationStart",
  "LayoutAnimationComplete"
];
var featureDefinitions = {};
function setFeatureDefinitions(definitions) {
  featureDefinitions = definitions;
}
var VisualElement = class {
  /**
   * This method takes React props and returns found MotionValues. For example, HTML
   * MotionValues will be found within the style prop, whereas for Three.js within attribute arrays.
   *
   * This isn't an abstract method as it needs calling in the constructor, but it is
   * intended to be one.
   */
  scrapeMotionValuesFromProps(_props, _prevProps, _visualElement) {
    return {};
  }
  constructor({ parent, props, presenceContext, reducedMotionConfig, skipAnimations, blockInitialAnimation, visualState }, options = {}) {
    this.current = null;
    this.children = /* @__PURE__ */ new Set();
    this.isVariantNode = false;
    this.isControllingVariants = false;
    this.shouldReduceMotion = null;
    this.shouldSkipAnimations = false;
    this.values = /* @__PURE__ */ new Map();
    this.KeyframeResolver = KeyframeResolver;
    this.features = {};
    this.valueSubscriptions = /* @__PURE__ */ new Map();
    this.prevMotionValues = {};
    this.hasBeenMounted = false;
    this.events = {};
    this.propEventSubscriptions = {};
    this.notifyUpdate = () => this.notify("Update", this.latestValues);
    this.render = () => {
      if (!this.current)
        return;
      this.triggerBuild();
      this.renderInstance(this.current, this.renderState, this.props.style, this.projection);
    };
    this.renderScheduledAt = 0;
    this.scheduleRender = () => {
      const now2 = time.now();
      if (this.renderScheduledAt < now2) {
        this.renderScheduledAt = now2;
        frame.render(this.render, false, true);
      }
    };
    const { latestValues, renderState } = visualState;
    this.latestValues = latestValues;
    this.baseTarget = { ...latestValues };
    this.initialValues = props.initial ? { ...latestValues } : {};
    this.renderState = renderState;
    this.parent = parent;
    this.props = props;
    this.presenceContext = presenceContext;
    this.depth = parent ? parent.depth + 1 : 0;
    this.reducedMotionConfig = reducedMotionConfig;
    this.skipAnimationsConfig = skipAnimations;
    this.options = options;
    this.blockInitialAnimation = Boolean(blockInitialAnimation);
    this.isControllingVariants = isControllingVariants(props);
    this.isVariantNode = isVariantNode(props);
    if (this.isVariantNode) {
      this.variantChildren = /* @__PURE__ */ new Set();
    }
    this.manuallyAnimateOnMount = Boolean(parent && parent.current);
    const { willChange, ...initialMotionValues } = this.scrapeMotionValuesFromProps(props, {}, this);
    for (const key in initialMotionValues) {
      const value = initialMotionValues[key];
      if (latestValues[key] !== void 0 && isMotionValue(value)) {
        value.set(latestValues[key]);
      }
    }
  }
  mount(instance) {
    if (this.hasBeenMounted) {
      for (const key in this.initialValues) {
        this.values.get(key)?.jump(this.initialValues[key]);
        this.latestValues[key] = this.initialValues[key];
      }
    }
    this.current = instance;
    visualElementStore.set(instance, this);
    if (this.projection && !this.projection.instance) {
      this.projection.mount(instance);
    }
    if (this.parent && this.isVariantNode && !this.isControllingVariants) {
      this.removeFromVariantTree = this.parent.addVariantChild(this);
    }
    this.values.forEach((value, key) => this.bindToMotionValue(key, value));
    if (this.reducedMotionConfig === "never") {
      this.shouldReduceMotion = false;
    } else if (this.reducedMotionConfig === "always") {
      this.shouldReduceMotion = true;
    } else {
      if (!hasReducedMotionListener.current) {
        initPrefersReducedMotion();
      }
      this.shouldReduceMotion = prefersReducedMotion.current;
    }
    if (true) {
      warnOnce(this.shouldReduceMotion !== true, "You have Reduced Motion enabled on your device. Animations may not appear as expected.", "reduced-motion-disabled");
    }
    this.shouldSkipAnimations = this.skipAnimationsConfig ?? false;
    this.parent?.addChild(this);
    this.update(this.props, this.presenceContext);
    this.hasBeenMounted = true;
  }
  unmount() {
    this.projection && this.projection.unmount();
    cancelFrame(this.notifyUpdate);
    cancelFrame(this.render);
    this.valueSubscriptions.forEach((remove) => remove());
    this.valueSubscriptions.clear();
    this.removeFromVariantTree && this.removeFromVariantTree();
    this.parent?.removeChild(this);
    for (const key in this.events) {
      this.events[key].clear();
    }
    for (const key in this.features) {
      const feature = this.features[key];
      if (feature) {
        feature.unmount();
        feature.isMounted = false;
      }
    }
    this.current = null;
  }
  addChild(child) {
    this.children.add(child);
    this.enteringChildren ?? (this.enteringChildren = /* @__PURE__ */ new Set());
    this.enteringChildren.add(child);
  }
  removeChild(child) {
    this.children.delete(child);
    this.enteringChildren && this.enteringChildren.delete(child);
  }
  bindToMotionValue(key, value) {
    if (this.valueSubscriptions.has(key)) {
      this.valueSubscriptions.get(key)();
    }
    if (value.accelerate && acceleratedValues.has(key) && this.current instanceof HTMLElement) {
      const { factory, keyframes: keyframes2, times, ease: ease3, duration } = value.accelerate;
      const animation = new NativeAnimation({
        element: this.current,
        name: key,
        keyframes: keyframes2,
        times,
        ease: ease3,
        duration: secondsToMilliseconds(duration)
      });
      const cleanup = factory(animation);
      this.valueSubscriptions.set(key, () => {
        cleanup();
        animation.cancel();
      });
      return;
    }
    const valueIsTransform = transformProps.has(key);
    if (valueIsTransform && this.onBindTransform) {
      this.onBindTransform();
    }
    const removeOnChange = value.on("change", (latestValue) => {
      this.latestValues[key] = latestValue;
      this.props.onUpdate && frame.preRender(this.notifyUpdate);
      if (valueIsTransform && this.projection) {
        this.projection.isTransformDirty = true;
      }
      this.scheduleRender();
    });
    let removeSyncCheck;
    if (typeof window !== "undefined" && window.MotionCheckAppearSync) {
      removeSyncCheck = window.MotionCheckAppearSync(this, key, value);
    }
    this.valueSubscriptions.set(key, () => {
      removeOnChange();
      if (removeSyncCheck)
        removeSyncCheck();
    });
  }
  sortNodePosition(other) {
    if (!this.current || !this.sortInstanceNodePosition || this.type !== other.type) {
      return 0;
    }
    return this.sortInstanceNodePosition(this.current, other.current);
  }
  updateFeatures() {
    let key = "animation";
    for (key in featureDefinitions) {
      const featureDefinition = featureDefinitions[key];
      if (!featureDefinition)
        continue;
      const { isEnabled: isEnabled2, Feature: FeatureConstructor } = featureDefinition;
      if (!this.features[key] && FeatureConstructor && isEnabled2(this.props)) {
        this.features[key] = new FeatureConstructor(this);
      }
      if (this.features[key]) {
        const feature = this.features[key];
        if (feature.isMounted) {
          feature.update();
        } else {
          feature.mount();
          feature.isMounted = true;
        }
      }
    }
  }
  triggerBuild() {
    this.build(this.renderState, this.latestValues, this.props);
  }
  /**
   * Measure the current viewport box with or without transforms.
   * Only measures axis-aligned boxes, rotate and skew must be manually
   * removed with a re-render to work.
   */
  measureViewportBox() {
    return this.current ? this.measureInstanceViewportBox(this.current, this.props) : createBox();
  }
  getStaticValue(key) {
    return this.latestValues[key];
  }
  setStaticValue(key, value) {
    this.latestValues[key] = value;
  }
  /**
   * Update the provided props. Ensure any newly-added motion values are
   * added to our map, old ones removed, and listeners updated.
   */
  update(props, presenceContext) {
    if (props.transformTemplate || this.props.transformTemplate) {
      this.scheduleRender();
    }
    this.prevProps = this.props;
    this.props = props;
    this.prevPresenceContext = this.presenceContext;
    this.presenceContext = presenceContext;
    for (let i = 0; i < propEventHandlers.length; i++) {
      const key = propEventHandlers[i];
      if (this.propEventSubscriptions[key]) {
        this.propEventSubscriptions[key]();
        delete this.propEventSubscriptions[key];
      }
      const listenerName = "on" + key;
      const listener = props[listenerName];
      if (listener) {
        this.propEventSubscriptions[key] = this.on(key, listener);
      }
    }
    this.prevMotionValues = updateMotionValuesFromProps(this, this.scrapeMotionValuesFromProps(props, this.prevProps || {}, this), this.prevMotionValues);
    if (this.handleChildMotionValue) {
      this.handleChildMotionValue();
    }
  }
  getProps() {
    return this.props;
  }
  /**
   * Returns the variant definition with a given name.
   */
  getVariant(name) {
    return this.props.variants ? this.props.variants[name] : void 0;
  }
  /**
   * Returns the defined default transition on this component.
   */
  getDefaultTransition() {
    return this.props.transition;
  }
  getTransformPagePoint() {
    return this.props.transformPagePoint;
  }
  getClosestVariantNode() {
    return this.isVariantNode ? this : this.parent ? this.parent.getClosestVariantNode() : void 0;
  }
  /**
   * Add a child visual element to our set of children.
   */
  addVariantChild(child) {
    const closestVariantNode = this.getClosestVariantNode();
    if (closestVariantNode) {
      closestVariantNode.variantChildren && closestVariantNode.variantChildren.add(child);
      return () => closestVariantNode.variantChildren.delete(child);
    }
  }
  /**
   * Add a motion value and bind it to this visual element.
   */
  addValue(key, value) {
    const existingValue = this.values.get(key);
    if (value !== existingValue) {
      if (existingValue)
        this.removeValue(key);
      this.bindToMotionValue(key, value);
      this.values.set(key, value);
      this.latestValues[key] = value.get();
    }
  }
  /**
   * Remove a motion value and unbind any active subscriptions.
   */
  removeValue(key) {
    this.values.delete(key);
    const unsubscribe = this.valueSubscriptions.get(key);
    if (unsubscribe) {
      unsubscribe();
      this.valueSubscriptions.delete(key);
    }
    delete this.latestValues[key];
    this.removeValueFromRenderState(key, this.renderState);
  }
  /**
   * Check whether we have a motion value for this key
   */
  hasValue(key) {
    return this.values.has(key);
  }
  getValue(key, defaultValue) {
    if (this.props.values && this.props.values[key]) {
      return this.props.values[key];
    }
    let value = this.values.get(key);
    if (value === void 0 && defaultValue !== void 0) {
      value = motionValue(defaultValue === null ? void 0 : defaultValue, { owner: this });
      this.addValue(key, value);
    }
    return value;
  }
  /**
   * If we're trying to animate to a previously unencountered value,
   * we need to check for it in our state and as a last resort read it
   * directly from the instance (which might have performance implications).
   */
  readValue(key, target) {
    let value = this.latestValues[key] !== void 0 || !this.current ? this.latestValues[key] : this.getBaseTargetFromProps(this.props, key) ?? this.readValueFromInstance(this.current, key, this.options);
    if (value !== void 0 && value !== null) {
      if (typeof value === "string" && (isNumericalString(value) || isZeroValueString(value))) {
        value = parseFloat(value);
      } else if (!findValueType(value) && complex.test(target)) {
        value = getAnimatableNone2(key, target);
      }
      this.setBaseTarget(key, isMotionValue(value) ? value.get() : value);
    }
    return isMotionValue(value) ? value.get() : value;
  }
  /**
   * Set the base target to later animate back to. This is currently
   * only hydrated on creation and when we first read a value.
   */
  setBaseTarget(key, value) {
    this.baseTarget[key] = value;
  }
  /**
   * Find the base target for a value thats been removed from all animation
   * props.
   */
  getBaseTarget(key) {
    const { initial } = this.props;
    let valueFromInitial;
    if (typeof initial === "string" || typeof initial === "object") {
      const variant = resolveVariantFromProps(this.props, initial, this.presenceContext?.custom);
      if (variant) {
        valueFromInitial = variant[key];
      }
    }
    if (initial && valueFromInitial !== void 0) {
      return valueFromInitial;
    }
    const target = this.getBaseTargetFromProps(this.props, key);
    if (target !== void 0 && !isMotionValue(target))
      return target;
    return this.initialValues[key] !== void 0 && valueFromInitial === void 0 ? void 0 : this.baseTarget[key];
  }
  on(eventName, callback) {
    if (!this.events[eventName]) {
      this.events[eventName] = new SubscriptionManager();
    }
    return this.events[eventName].add(callback);
  }
  notify(eventName, ...args) {
    if (this.events[eventName]) {
      this.events[eventName].notify(...args);
    }
  }
  scheduleRenderMicrotask() {
    microtask.render(this.render);
  }
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/dom/DOMVisualElement.mjs
var DOMVisualElement = class extends VisualElement {
  constructor() {
    super(...arguments);
    this.KeyframeResolver = DOMKeyframesResolver;
  }
  sortInstanceNodePosition(a, b) {
    return a.compareDocumentPosition(b) & 2 ? 1 : -1;
  }
  getBaseTargetFromProps(props, key) {
    const style2 = props.style;
    return style2 ? style2[key] : void 0;
  }
  removeValueFromRenderState(key, { vars, style: style2 }) {
    delete vars[key];
    delete style2[key];
  }
  handleChildMotionValue() {
    if (this.childSubscription) {
      this.childSubscription();
      delete this.childSubscription;
    }
    const { children } = this.props;
    if (isMotionValue(children)) {
      this.childSubscription = children.on("change", (latest) => {
        if (this.current) {
          this.current.textContent = `${latest}`;
        }
      });
    }
  }
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/Feature.mjs
var Feature = class {
  constructor(node) {
    this.isMounted = false;
    this.node = node;
  }
  update() {
  }
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/projection/geometry/conversion.mjs
function convertBoundingBoxToBox({ top, left, right, bottom }) {
  return {
    x: { min: left, max: right },
    y: { min: top, max: bottom }
  };
}
function convertBoxToBoundingBox({ x, y }) {
  return { top: y.min, right: x.max, bottom: y.max, left: x.min };
}
function transformBoxPoints(point2, transformPoint2) {
  if (!transformPoint2)
    return point2;
  const topLeft = transformPoint2({ x: point2.left, y: point2.top });
  const bottomRight = transformPoint2({ x: point2.right, y: point2.bottom });
  return {
    top: topLeft.y,
    left: topLeft.x,
    bottom: bottomRight.y,
    right: bottomRight.x
  };
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/projection/utils/has-transform.mjs
function isIdentityScale(scale2) {
  return scale2 === void 0 || scale2 === 1;
}
function hasScale({ scale: scale2, scaleX: scaleX2, scaleY: scaleY2 }) {
  return !isIdentityScale(scale2) || !isIdentityScale(scaleX2) || !isIdentityScale(scaleY2);
}
function hasTransform(values) {
  return hasScale(values) || has2DTranslate(values) || values.z || values.rotate || values.rotateX || values.rotateY || values.skewX || values.skewY;
}
function has2DTranslate(values) {
  return is2DTranslate(values.x) || is2DTranslate(values.y);
}
function is2DTranslate(value) {
  return value && value !== "0%";
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/projection/geometry/delta-apply.mjs
function scalePoint(point2, scale2, originPoint) {
  const distanceFromOrigin = point2 - originPoint;
  const scaled = scale2 * distanceFromOrigin;
  return originPoint + scaled;
}
function applyPointDelta(point2, translate, scale2, originPoint, boxScale) {
  if (boxScale !== void 0) {
    point2 = scalePoint(point2, boxScale, originPoint);
  }
  return scalePoint(point2, scale2, originPoint) + translate;
}
function applyAxisDelta(axis, translate = 0, scale2 = 1, originPoint, boxScale) {
  axis.min = applyPointDelta(axis.min, translate, scale2, originPoint, boxScale);
  axis.max = applyPointDelta(axis.max, translate, scale2, originPoint, boxScale);
}
function applyBoxDelta(box, { x, y }) {
  applyAxisDelta(box.x, x.translate, x.scale, x.originPoint);
  applyAxisDelta(box.y, y.translate, y.scale, y.originPoint);
}
var TREE_SCALE_SNAP_MIN = 0.999999999999;
var TREE_SCALE_SNAP_MAX = 1.0000000000001;
function applyTreeDeltas(box, treeScale, treePath, isSharedTransition = false) {
  const treeLength = treePath.length;
  if (!treeLength)
    return;
  treeScale.x = treeScale.y = 1;
  let node;
  let delta;
  for (let i = 0; i < treeLength; i++) {
    node = treePath[i];
    delta = node.projectionDelta;
    const { visualElement } = node.options;
    if (visualElement && visualElement.props.style && visualElement.props.style.display === "contents") {
      continue;
    }
    if (isSharedTransition && node.options.layoutScroll && node.scroll && node !== node.root) {
      translateAxis(box.x, -node.scroll.offset.x);
      translateAxis(box.y, -node.scroll.offset.y);
    }
    if (delta) {
      treeScale.x *= delta.x.scale;
      treeScale.y *= delta.y.scale;
      applyBoxDelta(box, delta);
    }
    if (isSharedTransition && hasTransform(node.latestValues)) {
      transformBox(box, node.latestValues, node.layout?.layoutBox);
    }
  }
  if (treeScale.x < TREE_SCALE_SNAP_MAX && treeScale.x > TREE_SCALE_SNAP_MIN) {
    treeScale.x = 1;
  }
  if (treeScale.y < TREE_SCALE_SNAP_MAX && treeScale.y > TREE_SCALE_SNAP_MIN) {
    treeScale.y = 1;
  }
}
function translateAxis(axis, distance2) {
  axis.min += distance2;
  axis.max += distance2;
}
function transformAxis(axis, axisTranslate, axisScale, boxScale, axisOrigin = 0.5) {
  const originPoint = mixNumber(axis.min, axis.max, axisOrigin);
  applyAxisDelta(axis, axisTranslate, axisScale, originPoint, boxScale);
}
function resolveAxisTranslate(value, axis) {
  if (typeof value === "string") {
    return parseFloat(value) / 100 * (axis.max - axis.min);
  }
  return value;
}
function transformBox(box, transform, sourceBox) {
  const resolveBox = sourceBox ?? box;
  transformAxis(box.x, resolveAxisTranslate(transform.x, resolveBox.x), transform.scaleX, transform.scale, transform.originX);
  transformAxis(box.y, resolveAxisTranslate(transform.y, resolveBox.y), transform.scaleY, transform.scale, transform.originY);
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/projection/utils/measure.mjs
function measureViewportBox(instance, transformPoint2) {
  return convertBoundingBoxToBox(transformBoxPoints(instance.getBoundingClientRect(), transformPoint2));
}
function measurePageBox(element, rootProjectionNode2, transformPagePoint) {
  const viewportBox = measureViewportBox(element, transformPagePoint);
  const { scroll: scroll2 } = rootProjectionNode2;
  if (scroll2) {
    translateAxis(viewportBox.x, scroll2.offset.x);
    translateAxis(viewportBox.y, scroll2.offset.y);
  }
  return viewportBox;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/html/utils/build-transform.mjs
var translateAlias = {
  x: "translateX",
  y: "translateY",
  z: "translateZ",
  transformPerspective: "perspective"
};
var numTransforms = transformPropOrder.length;
function buildTransform(latestValues, transform, transformTemplate) {
  let transformString = "";
  let transformIsDefault = true;
  for (let i = 0; i < numTransforms; i++) {
    const key = transformPropOrder[i];
    const value = latestValues[key];
    if (value === void 0)
      continue;
    let valueIsDefault = true;
    if (typeof value === "number") {
      valueIsDefault = value === (key.startsWith("scale") ? 1 : 0);
    } else {
      const parsed = parseFloat(value);
      valueIsDefault = key.startsWith("scale") ? parsed === 1 : parsed === 0;
    }
    if (!valueIsDefault || transformTemplate) {
      const valueAsType = getValueAsType(value, numberValueTypes[key]);
      if (!valueIsDefault) {
        transformIsDefault = false;
        const transformName = translateAlias[key] || key;
        transformString += `${transformName}(${valueAsType}) `;
      }
      if (transformTemplate) {
        transform[key] = valueAsType;
      }
    }
  }
  const pathRotation = latestValues.pathRotation;
  if (pathRotation) {
    transformIsDefault = false;
    transformString += `rotate(${getValueAsType(pathRotation, numberValueTypes.pathRotation)}) `;
  }
  transformString = transformString.trim();
  if (transformTemplate) {
    transformString = transformTemplate(transform, transformIsDefault ? "" : transformString);
  } else if (transformIsDefault) {
    transformString = "none";
  }
  return transformString;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/html/utils/build-styles.mjs
function buildHTMLStyles(state, latestValues, transformTemplate) {
  const { style: style2, vars, transformOrigin } = state;
  let hasTransform2 = false;
  let hasTransformOrigin = false;
  for (const key in latestValues) {
    const value = latestValues[key];
    if (transformProps.has(key)) {
      hasTransform2 = true;
      continue;
    } else if (isCSSVariableName(key)) {
      vars[key] = value;
      continue;
    } else {
      const valueAsType = getValueAsType(value, numberValueTypes[key]);
      if (key.startsWith("origin")) {
        hasTransformOrigin = true;
        transformOrigin[key] = valueAsType;
      } else {
        style2[key] = valueAsType;
      }
    }
  }
  if (!latestValues.transform) {
    if (hasTransform2 || transformTemplate) {
      style2.transform = buildTransform(latestValues, state.transform, transformTemplate);
    } else if (style2.transform) {
      style2.transform = "none";
    }
  }
  if (hasTransformOrigin) {
    const { originX = "50%", originY = "50%", originZ = 0 } = transformOrigin;
    style2.transformOrigin = `${originX} ${originY} ${originZ}`;
  }
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/html/utils/render.mjs
function renderHTML(element, { style: style2, vars }, styleProp, projection) {
  const elementStyle = element.style;
  let key;
  for (key in style2) {
    elementStyle[key] = style2[key];
  }
  projection?.applyProjectionStyles(elementStyle, styleProp);
  for (key in vars) {
    elementStyle.setProperty(key, vars[key]);
  }
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/projection/styles/scale-border-radius.mjs
function pixelsToPercent(pixels, axis) {
  if (axis.max === axis.min)
    return 0;
  return pixels / (axis.max - axis.min) * 100;
}
var correctBorderRadius = {
  correct: (latest, node) => {
    if (!node.target)
      return latest;
    if (typeof latest === "string") {
      if (px.test(latest)) {
        latest = parseFloat(latest);
      } else {
        return latest;
      }
    }
    const x = pixelsToPercent(latest, node.target.x);
    const y = pixelsToPercent(latest, node.target.y);
    return `${x}% ${y}%`;
  }
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/projection/styles/scale-box-shadow.mjs
var correctBoxShadow = {
  correct: (latest, { treeScale, projectionDelta }) => {
    const original = latest;
    const shadow = complex.parse(latest);
    if (shadow.length > 5)
      return original;
    const template = complex.createTransformer(latest);
    const offset = typeof shadow[0] !== "number" ? 1 : 0;
    const xScale = projectionDelta.x.scale * treeScale.x;
    const yScale = projectionDelta.y.scale * treeScale.y;
    shadow[0 + offset] /= xScale;
    shadow[1 + offset] /= yScale;
    const averageScale = mixNumber(xScale, yScale, 0.5);
    if (typeof shadow[2 + offset] === "number")
      shadow[2 + offset] /= averageScale;
    if (typeof shadow[3 + offset] === "number")
      shadow[3 + offset] /= averageScale;
    return template(shadow);
  }
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/projection/styles/scale-correction.mjs
var scaleCorrectors = {
  borderRadius: {
    ...correctBorderRadius,
    applyTo: [...cornerRadiusProps]
  },
  borderTopLeftRadius: correctBorderRadius,
  borderTopRightRadius: correctBorderRadius,
  borderBottomLeftRadius: correctBorderRadius,
  borderBottomRightRadius: correctBorderRadius,
  boxShadow: correctBoxShadow
};
function addScaleCorrector(correctors) {
  for (const key in correctors) {
    scaleCorrectors[key] = correctors[key];
    if (isCSSVariableName(key)) {
      scaleCorrectors[key].isCSSVariable = true;
    }
  }
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/utils/is-forced-motion-value.mjs
function isForcedMotionValue(key, { layout, layoutId }) {
  return transformProps.has(key) || key.startsWith("origin") || (layout || layoutId !== void 0) && (!!scaleCorrectors[key] || key === "opacity");
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/html/utils/scrape-motion-values.mjs
function scrapeMotionValuesFromProps(props, prevProps, visualElement) {
  const style2 = props.style;
  const prevStyle = prevProps?.style;
  const newValues = {};
  if (!style2)
    return newValues;
  for (const key in style2) {
    if (isMotionValue(style2[key]) || prevStyle && isMotionValue(prevStyle[key]) || isForcedMotionValue(key, props) || visualElement?.getValue(key)?.liveStyle !== void 0) {
      newValues[key] = style2[key];
    }
  }
  return newValues;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/html/HTMLVisualElement.mjs
function getComputedStyle2(element) {
  return window.getComputedStyle(element);
}
var HTMLVisualElement = class extends DOMVisualElement {
  constructor() {
    super(...arguments);
    this.type = "html";
    this.renderInstance = renderHTML;
  }
  mount(instance) {
    invariant(Boolean(instance.style), "motion.create() components must forward their ref to a HTML or SVG element", "custom-component-ref");
    super.mount(instance);
  }
  readValueFromInstance(instance, key) {
    if (transformProps.has(key)) {
      return this.projection?.isProjecting ? defaultTransformValue(key) : readTransformValue(instance, key);
    } else {
      const computedStyle = getComputedStyle2(instance);
      const value = (isCSSVariableName(key) ? computedStyle.getPropertyValue(key) : computedStyle[key]) || 0;
      return typeof value === "string" ? value.trim() : value;
    }
  }
  measureInstanceViewportBox(instance, { transformPagePoint }) {
    return measureViewportBox(instance, transformPagePoint);
  }
  build(renderState, latestValues, props) {
    buildHTMLStyles(renderState, latestValues, props.transformTemplate);
  }
  scrapeMotionValuesFromProps(props, prevProps, visualElement) {
    return scrapeMotionValuesFromProps(props, prevProps, visualElement);
  }
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/svg/utils/path.mjs
var dashKeys = {
  offset: "stroke-dashoffset",
  array: "stroke-dasharray"
};
var camelKeys = {
  offset: "strokeDashoffset",
  array: "strokeDasharray"
};
function buildSVGPath(attrs, length, spacing = 1, offset = 0, useDashCase = true) {
  attrs.pathLength = 1;
  const keys2 = useDashCase ? dashKeys : camelKeys;
  attrs[keys2.offset] = `${-offset}`;
  attrs[keys2.array] = `${length} ${spacing}`;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/svg/utils/build-attrs.mjs
var cssStyleProperties = [
  "transform",
  "opacity",
  "offsetDistance",
  "offsetPath",
  "offsetRotate",
  "offsetAnchor"
];
function buildSVGAttrs(state, {
  attrX,
  attrY,
  attrScale,
  pathLength,
  pathSpacing = 1,
  pathOffset = 0,
  // This is object creation, which we try to avoid per-frame.
  ...latest
}, isSVGTag2, transformTemplate, styleProp) {
  buildHTMLStyles(state, latest, transformTemplate);
  if (isSVGTag2) {
    if (state.style.viewBox) {
      state.attrs.viewBox = state.style.viewBox;
    }
    return;
  }
  state.attrs = state.style;
  state.style = {};
  const { attrs, style: style2 } = state;
  for (const key of cssStyleProperties) {
    if (attrs[key] !== void 0) {
      style2[key] = attrs[key];
      delete attrs[key];
    }
  }
  if (style2.transform || attrs.transformOrigin) {
    style2.transformOrigin = attrs.transformOrigin ?? "50% 50%";
    delete attrs.transformOrigin;
  }
  if (style2.transform) {
    style2.transformBox = styleProp?.transformBox ?? "fill-box";
    delete attrs.transformBox;
  }
  if (attrX !== void 0)
    attrs.x = attrX;
  if (attrY !== void 0)
    attrs.y = attrY;
  if (attrScale !== void 0)
    attrs.scale = attrScale;
  if (pathLength !== void 0) {
    buildSVGPath(attrs, pathLength, pathSpacing, pathOffset, false);
  }
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/svg/utils/camel-case-attrs.mjs
var camelCaseAttributes = /* @__PURE__ */ new Set([
  "baseFrequency",
  "diffuseConstant",
  "kernelMatrix",
  "kernelUnitLength",
  "keySplines",
  "keyTimes",
  "limitingConeAngle",
  "markerHeight",
  "markerWidth",
  "numOctaves",
  "targetX",
  "targetY",
  "surfaceScale",
  "specularConstant",
  "specularExponent",
  "stdDeviation",
  "tableValues",
  "viewBox",
  "gradientTransform",
  "pathLength",
  "startOffset",
  "textLength",
  "lengthAdjust"
]);

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/svg/utils/is-svg-tag.mjs
var isSVGTag = (tag) => typeof tag === "string" && tag.toLowerCase() === "svg";

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/svg/utils/render.mjs
function renderSVG(element, renderState, _styleProp, projection) {
  renderHTML(element, renderState, void 0, projection);
  for (const key in renderState.attrs) {
    element.setAttribute(!camelCaseAttributes.has(key) ? camelToDash(key) : key, renderState.attrs[key]);
  }
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/svg/utils/scrape-motion-values.mjs
function scrapeMotionValuesFromProps2(props, prevProps, visualElement) {
  const newValues = scrapeMotionValuesFromProps(props, prevProps, visualElement);
  for (const key in props) {
    if (isMotionValue(props[key]) || isMotionValue(prevProps[key])) {
      const targetKey = transformPropOrder.indexOf(key) !== -1 ? "attr" + key.charAt(0).toUpperCase() + key.substring(1) : key;
      newValues[targetKey] = props[key];
    }
  }
  return newValues;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/svg/SVGVisualElement.mjs
var SVGVisualElement = class extends DOMVisualElement {
  constructor() {
    super(...arguments);
    this.type = "svg";
    this.isSVGTag = false;
    this.measureInstanceViewportBox = createBox;
  }
  getBaseTargetFromProps(props, key) {
    return props[key];
  }
  readValueFromInstance(instance, key) {
    if (transformProps.has(key)) {
      const defaultType = getDefaultValueType(key);
      return defaultType ? defaultType.default || 0 : 0;
    }
    if (cssStyleProperties.includes(key)) {
      const computedStyle = getComputedStyle(instance);
      const value = computedStyle[key];
      if (typeof value === "string" && value)
        return value.trim();
    }
    key = !camelCaseAttributes.has(key) ? camelToDash(key) : key;
    return instance.getAttribute(key);
  }
  scrapeMotionValuesFromProps(props, prevProps, visualElement) {
    return scrapeMotionValuesFromProps2(props, prevProps, visualElement);
  }
  build(renderState, latestValues, props) {
    buildSVGAttrs(renderState, latestValues, this.isSVGTag, props.transformTemplate, props.style);
  }
  renderInstance(instance, renderState, styleProp, projection) {
    renderSVG(instance, renderState, styleProp, projection);
  }
  mount(instance) {
    this.isSVGTag = isSVGTag(instance.tagName);
    super.mount(instance);
  }
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/utils/get-variant-context.mjs
var numVariantProps = variantProps.length;
function getVariantContext(visualElement) {
  if (!visualElement)
    return void 0;
  if (!visualElement.isControllingVariants) {
    const context2 = visualElement.parent ? getVariantContext(visualElement.parent) || {} : {};
    if (visualElement.props.initial !== void 0) {
      context2.initial = visualElement.props.initial;
    }
    return context2;
  }
  const context = {};
  for (let i = 0; i < numVariantProps; i++) {
    const name = variantProps[i];
    const prop = visualElement.props[name];
    if (isVariantLabel(prop) || prop === false) {
      context[name] = prop;
    }
  }
  return context;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/utils/shallow-compare.mjs
function shallowCompare(next2, prev) {
  if (!Array.isArray(prev))
    return false;
  const prevLength = prev.length;
  if (prevLength !== next2.length)
    return false;
  for (let i = 0; i < prevLength; i++) {
    if (prev[i] !== next2[i])
      return false;
  }
  return true;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/render/utils/animation-state.mjs
var reversePriorityOrder = [...variantPriorityOrder].reverse();
var numAnimationTypes = variantPriorityOrder.length;
function createAnimateFunction(visualElement) {
  return (animations) => {
    return Promise.all(animations.map(({ animation, options }) => animateVisualElement(visualElement, animation, options)));
  };
}
function createAnimationState(visualElement) {
  let animate = createAnimateFunction(visualElement);
  let state = createState();
  let isInitialRender = true;
  let wasReset = false;
  const buildResolvedTypeValues = (type) => (acc, definition) => {
    const resolved = resolveVariant(visualElement, definition, type === "exit" ? visualElement.presenceContext?.custom : void 0);
    if (resolved) {
      const { transition, transitionEnd, ...target } = resolved;
      acc = { ...acc, ...target, ...transitionEnd };
    }
    return acc;
  };
  function setAnimateFunction(makeAnimator) {
    animate = makeAnimator(visualElement);
  }
  function animateChanges(changedActiveType) {
    const { props } = visualElement;
    const context = getVariantContext(visualElement.parent) || {};
    const animations = [];
    const removedKeys = /* @__PURE__ */ new Set();
    let encounteredKeys = {};
    let removedVariantIndex = Infinity;
    for (let i = 0; i < numAnimationTypes; i++) {
      const type = reversePriorityOrder[i];
      const typeState = state[type];
      const prop = props[type] !== void 0 ? props[type] : context[type];
      const propIsVariant = isVariantLabel(prop);
      const activeDelta = type === changedActiveType ? typeState.isActive : null;
      if (activeDelta === false)
        removedVariantIndex = i;
      let isInherited = prop === context[type] && prop !== props[type] && propIsVariant;
      if (isInherited && (isInitialRender || wasReset) && visualElement.manuallyAnimateOnMount) {
        isInherited = false;
      }
      typeState.protectedKeys = { ...encounteredKeys };
      if (
        // If it isn't active and hasn't *just* been set as inactive
        !typeState.isActive && activeDelta === null || // If we didn't and don't have any defined prop for this animation type
        !prop && !typeState.prevProp || // Or if the prop doesn't define an animation
        isAnimationControls(prop) || typeof prop === "boolean"
      ) {
        continue;
      }
      if (type === "exit" && typeState.isActive && activeDelta !== true) {
        if (typeState.prevResolvedValues) {
          encounteredKeys = {
            ...encounteredKeys,
            ...typeState.prevResolvedValues
          };
        }
        continue;
      }
      const variantDidChange = checkVariantsDidChange(typeState.prevProp, prop);
      let shouldAnimateType = variantDidChange || // If we're making this variant active, we want to always make it active
      type === changedActiveType && typeState.isActive && !isInherited && propIsVariant || // If we removed a higher-priority variant (i is in reverse order)
      i > removedVariantIndex && propIsVariant;
      let handledRemovedValues = false;
      const definitionList = Array.isArray(prop) ? prop : [prop];
      let resolvedValues = definitionList.reduce(buildResolvedTypeValues(type), {});
      if (activeDelta === false)
        resolvedValues = {};
      const { prevResolvedValues = {} } = typeState;
      const allKeys = {
        ...prevResolvedValues,
        ...resolvedValues
      };
      const markToAnimate = (key) => {
        shouldAnimateType = true;
        if (removedKeys.has(key)) {
          handledRemovedValues = true;
          removedKeys.delete(key);
        }
        typeState.needsAnimating[key] = true;
        const motionValue2 = visualElement.getValue(key);
        if (motionValue2)
          motionValue2.liveStyle = false;
      };
      for (const key in allKeys) {
        const next2 = resolvedValues[key];
        const prev = prevResolvedValues[key];
        if (encounteredKeys.hasOwnProperty(key))
          continue;
        let valueHasChanged = false;
        if (isKeyframesTarget(next2) && isKeyframesTarget(prev)) {
          valueHasChanged = !shallowCompare(next2, prev) || variantDidChange;
        } else {
          valueHasChanged = next2 !== prev;
        }
        if (valueHasChanged) {
          if (next2 !== void 0 && next2 !== null) {
            markToAnimate(key);
          } else {
            removedKeys.add(key);
          }
        } else if (next2 !== void 0 && removedKeys.has(key)) {
          markToAnimate(key);
        } else {
          typeState.protectedKeys[key] = true;
        }
      }
      typeState.prevProp = prop;
      typeState.prevResolvedValues = resolvedValues;
      if (typeState.isActive) {
        encounteredKeys = { ...encounteredKeys, ...resolvedValues };
      }
      if ((isInitialRender || wasReset) && visualElement.blockInitialAnimation) {
        shouldAnimateType = false;
      }
      const willAnimateViaParent = isInherited && variantDidChange;
      const needsAnimating = !willAnimateViaParent || handledRemovedValues;
      if (shouldAnimateType && needsAnimating) {
        animations.push(...definitionList.map((animation) => {
          const options = { type };
          if (typeof animation === "string" && (isInitialRender || wasReset) && !willAnimateViaParent && visualElement.manuallyAnimateOnMount && visualElement.parent) {
            const { parent } = visualElement;
            const parentVariant = resolveVariant(parent, animation);
            if (parent.enteringChildren && parentVariant) {
              const { delayChildren } = parentVariant.transition || {};
              options.delay = calcChildStagger(parent.enteringChildren, visualElement, delayChildren);
            }
          }
          return {
            animation,
            options
          };
        }));
      }
    }
    if (removedKeys.size) {
      const fallbackAnimation = {};
      if (typeof props.initial !== "boolean") {
        const initialTransition = resolveVariant(visualElement, Array.isArray(props.initial) ? props.initial[0] : props.initial);
        if (initialTransition && initialTransition.transition) {
          fallbackAnimation.transition = initialTransition.transition;
        }
      }
      removedKeys.forEach((key) => {
        const fallbackTarget = visualElement.getBaseTarget(key);
        const motionValue2 = visualElement.getValue(key);
        if (motionValue2)
          motionValue2.liveStyle = true;
        fallbackAnimation[key] = fallbackTarget ?? null;
      });
      animations.push({ animation: fallbackAnimation });
    }
    let shouldAnimate = Boolean(animations.length);
    if (isInitialRender && (props.initial === false || props.initial === props.animate) && !visualElement.manuallyAnimateOnMount) {
      shouldAnimate = false;
    }
    isInitialRender = false;
    wasReset = false;
    return shouldAnimate ? animate(animations) : Promise.resolve();
  }
  function setActive(type, isActive) {
    if (state[type].isActive === isActive)
      return Promise.resolve();
    visualElement.variantChildren?.forEach((child) => child.animationState?.setActive(type, isActive));
    state[type].isActive = isActive;
    const animations = animateChanges(type);
    for (const key in state) {
      state[key].protectedKeys = {};
    }
    return animations;
  }
  return {
    animateChanges,
    setActive,
    setAnimateFunction,
    getState: () => state,
    reset: () => {
      state = createState();
      wasReset = true;
    }
  };
}
function checkVariantsDidChange(prev, next2) {
  if (typeof next2 === "string") {
    return next2 !== prev;
  } else if (Array.isArray(next2)) {
    return !shallowCompare(next2, prev);
  }
  return false;
}
function createTypeState(isActive = false) {
  return {
    isActive,
    protectedKeys: {},
    needsAnimating: {},
    prevResolvedValues: {}
  };
}
function createState() {
  return {
    animate: createTypeState(true),
    whileInView: createTypeState(),
    whileHover: createTypeState(),
    whileTap: createTypeState(),
    whileDrag: createTypeState(),
    whileFocus: createTypeState(),
    exit: createTypeState()
  };
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/projection/geometry/copy.mjs
function copyAxisInto(axis, originAxis) {
  axis.min = originAxis.min;
  axis.max = originAxis.max;
}
function copyBoxInto(box, originBox) {
  copyAxisInto(box.x, originBox.x);
  copyAxisInto(box.y, originBox.y);
}
function copyAxisDeltaInto(delta, originDelta) {
  delta.translate = originDelta.translate;
  delta.scale = originDelta.scale;
  delta.originPoint = originDelta.originPoint;
  delta.origin = originDelta.origin;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/projection/geometry/delta-calc.mjs
var SCALE_PRECISION = 1e-4;
var SCALE_MIN = 1 - SCALE_PRECISION;
var SCALE_MAX = 1 + SCALE_PRECISION;
var TRANSLATE_PRECISION = 0.01;
var TRANSLATE_MIN = 0 - TRANSLATE_PRECISION;
var TRANSLATE_MAX = 0 + TRANSLATE_PRECISION;
function calcLength(axis) {
  return axis.max - axis.min;
}
function isNear(value, target, maxDistance) {
  return Math.abs(value - target) <= maxDistance;
}
function calcAxisDelta(delta, source, target, origin = 0.5) {
  delta.origin = origin;
  delta.originPoint = mixNumber(source.min, source.max, delta.origin);
  delta.scale = calcLength(target) / calcLength(source);
  delta.translate = mixNumber(target.min, target.max, delta.origin) - delta.originPoint;
  if (delta.scale >= SCALE_MIN && delta.scale <= SCALE_MAX || isNaN(delta.scale)) {
    delta.scale = 1;
  }
  if (delta.translate >= TRANSLATE_MIN && delta.translate <= TRANSLATE_MAX || isNaN(delta.translate)) {
    delta.translate = 0;
  }
}
function calcBoxDelta(delta, source, target, origin) {
  calcAxisDelta(delta.x, source.x, target.x, origin ? origin.originX : void 0);
  calcAxisDelta(delta.y, source.y, target.y, origin ? origin.originY : void 0);
}
function calcRelativeAxis(target, relative, parent, anchor = 0) {
  const anchorPoint = anchor ? mixNumber(parent.min, parent.max, anchor) : parent.min;
  target.min = anchorPoint + relative.min;
  target.max = target.min + calcLength(relative);
}
function calcRelativeBox(target, relative, parent, anchor) {
  calcRelativeAxis(target.x, relative.x, parent.x, anchor?.x);
  calcRelativeAxis(target.y, relative.y, parent.y, anchor?.y);
}
function calcRelativeAxisPosition(target, layout, parent, anchor = 0) {
  const anchorPoint = anchor ? mixNumber(parent.min, parent.max, anchor) : parent.min;
  target.min = layout.min - anchorPoint;
  target.max = target.min + calcLength(layout);
}
function calcRelativePosition(target, layout, parent, anchor) {
  calcRelativeAxisPosition(target.x, layout.x, parent.x, anchor?.x);
  calcRelativeAxisPosition(target.y, layout.y, parent.y, anchor?.y);
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/projection/geometry/delta-remove.mjs
function removePointDelta(point2, translate, scale2, originPoint, boxScale) {
  point2 -= translate;
  point2 = scalePoint(point2, 1 / scale2, originPoint);
  if (boxScale !== void 0) {
    point2 = scalePoint(point2, 1 / boxScale, originPoint);
  }
  return point2;
}
function removeAxisDelta(axis, translate = 0, scale2 = 1, origin = 0.5, boxScale, originAxis = axis, sourceAxis = axis) {
  if (percent.test(translate)) {
    translate = parseFloat(translate);
    const relativeProgress = mixNumber(sourceAxis.min, sourceAxis.max, translate / 100);
    translate = relativeProgress - sourceAxis.min;
  }
  if (typeof translate !== "number")
    return;
  let originPoint = mixNumber(originAxis.min, originAxis.max, origin);
  if (axis === originAxis)
    originPoint -= translate;
  axis.min = removePointDelta(axis.min, translate, scale2, originPoint, boxScale);
  axis.max = removePointDelta(axis.max, translate, scale2, originPoint, boxScale);
}
function removeAxisTransforms(axis, transforms, [key, scaleKey, originKey], origin, sourceAxis) {
  removeAxisDelta(axis, transforms[key], transforms[scaleKey], transforms[originKey], transforms.scale, origin, sourceAxis);
}
var xKeys = ["x", "scaleX", "originX"];
var yKeys = ["y", "scaleY", "originY"];
function removeBoxTransforms(box, transforms, originBox, sourceBox) {
  removeAxisTransforms(box.x, transforms, xKeys, originBox ? originBox.x : void 0, sourceBox ? sourceBox.x : void 0);
  removeAxisTransforms(box.y, transforms, yKeys, originBox ? originBox.y : void 0, sourceBox ? sourceBox.y : void 0);
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/projection/geometry/utils.mjs
function isAxisDeltaZero(delta) {
  return delta.translate === 0 && delta.scale === 1;
}
function isDeltaZero(delta) {
  return isAxisDeltaZero(delta.x) && isAxisDeltaZero(delta.y);
}
function axisEquals(a, b) {
  return a.min === b.min && a.max === b.max;
}
function boxEquals(a, b) {
  return axisEquals(a.x, b.x) && axisEquals(a.y, b.y);
}
function axisEqualsRounded(a, b) {
  return Math.round(a.min) === Math.round(b.min) && Math.round(a.max) === Math.round(b.max);
}
function boxEqualsRounded(a, b) {
  return axisEqualsRounded(a.x, b.x) && axisEqualsRounded(a.y, b.y);
}
function aspectRatio(box) {
  return calcLength(box.x) / calcLength(box.y);
}
function axisDeltaEquals(a, b) {
  return a.translate === b.translate && a.scale === b.scale && a.originPoint === b.originPoint;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/projection/utils/each-axis.mjs
function eachAxis(callback) {
  return [callback("x"), callback("y")];
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/projection/styles/transform.mjs
function buildProjectionTransform(delta, treeScale, latestTransform) {
  let transform = "";
  const xTranslate = delta.x.translate / treeScale.x;
  const yTranslate = delta.y.translate / treeScale.y;
  const zTranslate = latestTransform?.z || 0;
  if (xTranslate || yTranslate || zTranslate) {
    transform = `translate3d(${xTranslate}px, ${yTranslate}px, ${zTranslate}px) `;
  }
  if (treeScale.x !== 1 || treeScale.y !== 1) {
    transform += `scale(${1 / treeScale.x}, ${1 / treeScale.y}) `;
  }
  if (latestTransform) {
    const { transformPerspective, rotate: rotate2, pathRotation, rotateX, rotateY, skewX, skewY } = latestTransform;
    if (transformPerspective)
      transform = `perspective(${transformPerspective}px) ${transform}`;
    if (rotate2)
      transform += `rotate(${rotate2}deg) `;
    if (pathRotation)
      transform += `rotate(${pathRotation}deg) `;
    if (rotateX)
      transform += `rotateX(${rotateX}deg) `;
    if (rotateY)
      transform += `rotateY(${rotateY}deg) `;
    if (skewX)
      transform += `skewX(${skewX}deg) `;
    if (skewY)
      transform += `skewY(${skewY}deg) `;
  }
  const elementScaleX = delta.x.scale * treeScale.x;
  const elementScaleY = delta.y.scale * treeScale.y;
  if (elementScaleX !== 1 || elementScaleY !== 1) {
    transform += `scale(${elementScaleX}, ${elementScaleY})`;
  }
  return transform || "none";
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/projection/animation/mix-values.mjs
var numBorders = cornerRadiusProps.length;
var asNumber = (value) => typeof value === "string" ? parseFloat(value) : value;
var isPx = (value) => typeof value === "number" || px.test(value);
function mixValues(target, follow, lead, progress2, shouldCrossfadeOpacity, isOnlyMember) {
  if (shouldCrossfadeOpacity) {
    target.opacity = mixNumber(0, lead.opacity ?? 1, easeCrossfadeIn(progress2));
    target.opacityExit = mixNumber(follow.opacity ?? 1, 0, easeCrossfadeOut(progress2));
  } else if (isOnlyMember) {
    target.opacity = mixNumber(follow.opacity ?? 1, lead.opacity ?? 1, progress2);
  }
  for (let i = 0; i < numBorders; i++) {
    const borderLabel = cornerRadiusProps[i];
    let followRadius = getRadius(follow, borderLabel);
    let leadRadius = getRadius(lead, borderLabel);
    if (followRadius === void 0 && leadRadius === void 0)
      continue;
    followRadius || (followRadius = 0);
    leadRadius || (leadRadius = 0);
    const canMix = followRadius === 0 || leadRadius === 0 || isPx(followRadius) === isPx(leadRadius);
    if (canMix) {
      target[borderLabel] = Math.max(mixNumber(asNumber(followRadius), asNumber(leadRadius), progress2), 0);
      if (percent.test(leadRadius) || percent.test(followRadius)) {
        target[borderLabel] += "%";
      }
    } else {
      target[borderLabel] = leadRadius;
    }
  }
  if (follow.rotate || lead.rotate) {
    target.rotate = mixNumber(follow.rotate || 0, lead.rotate || 0, progress2);
  }
}
function getRadius(values, radiusName) {
  return values[radiusName] !== void 0 ? values[radiusName] : values.borderRadius;
}
var easeCrossfadeIn = /* @__PURE__ */ compress(0, 0.5, circOut);
var easeCrossfadeOut = /* @__PURE__ */ compress(0.5, 0.95, noop);
function compress(min, max, easing) {
  return (p) => {
    if (p < min)
      return 0;
    if (p > max)
      return 1;
    return easing(progress(min, max, p));
  };
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/animation/animate/single-value.mjs
function animateSingleValue(value, keyframes2, options) {
  const motionValue$1 = isMotionValue(value) ? value : motionValue(value);
  motionValue$1.start(animateMotionValue("", motionValue$1, keyframes2, options));
  return motionValue$1.animation;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/events/add-dom-event.mjs
function addDomEvent(target, eventName, handler, options = { passive: true }) {
  target.addEventListener(eventName, handler, options);
  return () => target.removeEventListener(eventName, handler, options);
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/projection/utils/compare-by-depth.mjs
var compareByDepth = (a, b) => a.depth - b.depth;

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/projection/utils/flat-tree.mjs
var FlatTree = class {
  constructor() {
    this.children = [];
    this.isDirty = false;
  }
  add(child) {
    addUniqueItem(this.children, child);
    this.isDirty = true;
  }
  remove(child) {
    removeItem(this.children, child);
    this.isDirty = true;
  }
  forEach(callback) {
    this.isDirty && this.children.sort(compareByDepth);
    this.isDirty = false;
    this.children.forEach(callback);
  }
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/utils/delay.mjs
function delay(callback, timeout) {
  const start2 = time.now();
  const checkElapsed = ({ timestamp }) => {
    const elapsed = timestamp - start2;
    if (elapsed >= timeout) {
      cancelFrame(checkElapsed);
      callback(elapsed - timeout);
    }
  };
  frame.setup(checkElapsed, true);
  return () => cancelFrame(checkElapsed);
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/value/utils/resolve-motion-value.mjs
function resolveMotionValue(value) {
  return isMotionValue(value) ? value.get() : value;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/projection/shared/stack.mjs
var NodeStack = class {
  constructor() {
    this.members = [];
  }
  add(node) {
    addUniqueItem(this.members, node);
    for (let i = this.members.length - 1; i >= 0; i--) {
      const member = this.members[i];
      if (member === node || member === this.lead || member === this.prevLead)
        continue;
      const inst = member.instance;
      if ((!inst || inst.isConnected === false) && !member.snapshot) {
        removeItem(this.members, member);
        member.unmount();
      }
    }
    node.scheduleRender();
  }
  remove(node) {
    removeItem(this.members, node);
    if (node === this.prevLead)
      this.prevLead = void 0;
    if (node === this.lead) {
      const prevLead = this.members[this.members.length - 1];
      if (prevLead)
        this.promote(prevLead);
    }
  }
  relegate(node) {
    for (let i = this.members.indexOf(node) - 1; i >= 0; i--) {
      const member = this.members[i];
      if (member.isPresent !== false && member.instance?.isConnected !== false) {
        this.promote(member);
        return true;
      }
    }
    return false;
  }
  promote(node, preserveFollowOpacity) {
    const prevLead = this.lead;
    if (node === prevLead)
      return;
    this.prevLead = prevLead;
    this.lead = node;
    node.show();
    if (prevLead) {
      prevLead.updateSnapshot();
      node.scheduleRender();
      const { layoutDependency: prevDep } = prevLead.options;
      const { layoutDependency: nextDep } = node.options;
      if (prevDep === void 0 || prevDep !== nextDep) {
        node.resumeFrom = prevLead;
        if (preserveFollowOpacity)
          prevLead.preserveOpacity = true;
        if (prevLead.snapshot) {
          node.snapshot = prevLead.snapshot;
          node.snapshot.latestValues = prevLead.animationValues || prevLead.latestValues;
        }
        if (node.root?.isUpdating)
          node.isLayoutDirty = true;
      }
      if (node.options.crossfade === false)
        prevLead.hide();
    }
  }
  exitAnimationComplete() {
    this.members.forEach((member) => {
      member.options.onExitComplete?.();
      member.resumingFrom?.options.onExitComplete?.();
    });
  }
  scheduleRender() {
    this.members.forEach((member) => member.instance && member.scheduleRender(false));
  }
  removeLeadSnapshot() {
    if (this.lead?.snapshot)
      this.lead.snapshot = void 0;
  }
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/projection/node/state.mjs
var globalProjectionState = {
  /**
   * Global flag as to whether the tree has animated since the last time
   * we resized the window
   */
  hasAnimatedSinceResize: true,
  /**
   * We set this to true once, on the first update. Any nodes added to the tree beyond that
   * update will be given a `data-projection-id` attribute.
   */
  hasEverUpdated: false
};

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/projection/node/create-projection-node.mjs
var metrics = {
  nodes: 0,
  calculatedTargetDeltas: 0,
  calculatedProjections: 0
};
var transformAxes = ["", "X", "Y", "Z"];
var animationTarget = 1e3;
var id = 0;
function resetDistortingTransform(key, visualElement, values, sharedAnimationValues) {
  const { latestValues } = visualElement;
  if (latestValues[key]) {
    values[key] = latestValues[key];
    visualElement.setStaticValue(key, 0);
    if (sharedAnimationValues) {
      sharedAnimationValues[key] = 0;
    }
  }
}
function cancelTreeOptimisedTransformAnimations(projectionNode) {
  projectionNode.hasCheckedOptimisedAppear = true;
  if (projectionNode.root === projectionNode)
    return;
  const { visualElement } = projectionNode.options;
  if (!visualElement)
    return;
  const appearId = getOptimisedAppearId(visualElement);
  if (window.MotionHasOptimisedAnimation(appearId, "transform")) {
    const { layout, layoutId } = projectionNode.options;
    window.MotionCancelOptimisedAnimation(appearId, "transform", frame, !(layout || layoutId));
  }
  const { parent } = projectionNode;
  if (parent && !parent.hasCheckedOptimisedAppear) {
    cancelTreeOptimisedTransformAnimations(parent);
  }
}
function createProjectionNode({ attachResizeListener, defaultParent, measureScroll, checkIsScrollRoot, resetTransform }) {
  return class ProjectionNode {
    constructor(latestValues = {}, parent = defaultParent?.()) {
      this.id = id++;
      this.animationId = 0;
      this.animationCommitId = 0;
      this.children = /* @__PURE__ */ new Set();
      this.options = {};
      this.isTreeAnimating = false;
      this.isAnimationBlocked = false;
      this.isLayoutDirty = false;
      this.isProjectionDirty = false;
      this.isSharedProjectionDirty = false;
      this.isTransformDirty = false;
      this.updateManuallyBlocked = false;
      this.updateBlockedByResize = false;
      this.isUpdating = false;
      this.isSVG = false;
      this.needsReset = false;
      this.shouldResetTransform = false;
      this.hasCheckedOptimisedAppear = false;
      this.treeScale = { x: 1, y: 1 };
      this.eventHandlers = /* @__PURE__ */ new Map();
      this.hasTreeAnimated = false;
      this.layoutVersion = 0;
      this.updateScheduled = false;
      this.scheduleUpdate = () => this.update();
      this.projectionUpdateScheduled = false;
      this.checkUpdateFailed = () => {
        if (this.isUpdating) {
          this.isUpdating = false;
          this.clearAllSnapshots();
        }
      };
      this.updateProjection = () => {
        this.projectionUpdateScheduled = false;
        if (statsBuffer.value) {
          metrics.nodes = metrics.calculatedTargetDeltas = metrics.calculatedProjections = 0;
        }
        this.nodes.forEach(propagateDirtyNodes);
        this.nodes.forEach(resolveTargetDelta);
        this.nodes.forEach(calcProjection);
        this.nodes.forEach(cleanDirtyNodes);
        if (statsBuffer.addProjectionMetrics) {
          statsBuffer.addProjectionMetrics(metrics);
        }
      };
      this.resolvedRelativeTargetAt = 0;
      this.linkedParentVersion = 0;
      this.hasProjected = false;
      this.isVisible = true;
      this.animationProgress = 0;
      this.sharedNodes = /* @__PURE__ */ new Map();
      this.latestValues = latestValues;
      this.root = parent ? parent.root || parent : this;
      this.path = parent ? [...parent.path, parent] : [];
      this.parent = parent;
      this.depth = parent ? parent.depth + 1 : 0;
      for (let i = 0; i < this.path.length; i++) {
        this.path[i].shouldResetTransform = true;
      }
      if (this.root === this)
        this.nodes = new FlatTree();
    }
    addEventListener(name, handler) {
      if (!this.eventHandlers.has(name)) {
        this.eventHandlers.set(name, new SubscriptionManager());
      }
      return this.eventHandlers.get(name).add(handler);
    }
    notifyListeners(name, ...args) {
      const subscriptionManager = this.eventHandlers.get(name);
      subscriptionManager && subscriptionManager.notify(...args);
    }
    hasListeners(name) {
      return this.eventHandlers.has(name);
    }
    /**
     * Lifecycles
     */
    mount(instance) {
      if (this.instance)
        return;
      this.isSVG = isSVGElement(instance) && !isSVGSVGElement(instance);
      this.instance = instance;
      const { layoutId, layout, visualElement } = this.options;
      if (visualElement && !visualElement.current) {
        visualElement.mount(instance);
      }
      this.root.nodes.add(this);
      this.parent && this.parent.children.add(this);
      if (this.root.hasTreeAnimated && (layout || layoutId)) {
        this.isLayoutDirty = true;
      }
      if (attachResizeListener) {
        let cancelDelay;
        let innerWidth = 0;
        const resizeUnblockUpdate = () => this.root.updateBlockedByResize = false;
        frame.read(() => {
          innerWidth = window.innerWidth;
        });
        attachResizeListener(instance, () => {
          const newInnerWidth = window.innerWidth;
          if (newInnerWidth === innerWidth)
            return;
          innerWidth = newInnerWidth;
          this.root.updateBlockedByResize = true;
          cancelDelay && cancelDelay();
          cancelDelay = delay(resizeUnblockUpdate, 250);
          if (globalProjectionState.hasAnimatedSinceResize) {
            globalProjectionState.hasAnimatedSinceResize = false;
            this.nodes.forEach(finishAnimation);
          }
        });
      }
      if (layoutId) {
        this.root.registerSharedNode(layoutId, this);
      }
      if (this.options.animate !== false && visualElement && (layoutId || layout)) {
        this.addEventListener("didUpdate", ({ delta, hasLayoutChanged, hasRelativeLayoutChanged, layout: newLayout }) => {
          if (this.isTreeAnimationBlocked()) {
            this.target = void 0;
            this.relativeTarget = void 0;
            return;
          }
          const layoutTransition = this.options.transition || visualElement.getDefaultTransition() || defaultLayoutTransition;
          const { onLayoutAnimationStart, onLayoutAnimationComplete } = visualElement.getProps();
          const hasTargetChanged = !this.targetLayout || !boxEqualsRounded(this.targetLayout, newLayout);
          const hasOnlyRelativeTargetChanged = !hasLayoutChanged && hasRelativeLayoutChanged;
          if (this.options.layoutRoot || this.resumeFrom || hasOnlyRelativeTargetChanged || hasLayoutChanged && (hasTargetChanged || !this.currentAnimation)) {
            if (this.resumeFrom) {
              this.resumingFrom = this.resumeFrom;
              this.resumingFrom.resumingFrom = void 0;
            }
            const animationOptions = {
              ...getValueTransition(layoutTransition, "layout"),
              onPlay: onLayoutAnimationStart,
              onComplete: onLayoutAnimationComplete
            };
            if (visualElement.shouldReduceMotion || this.options.layoutRoot) {
              animationOptions.delay = 0;
              animationOptions.type = false;
            }
            this.startAnimation(animationOptions);
            this.setAnimationOrigin(delta, hasOnlyRelativeTargetChanged, animationOptions.path);
          } else {
            if (!hasLayoutChanged) {
              finishAnimation(this);
            }
            if (this.isLead() && this.options.onExitComplete) {
              this.options.onExitComplete();
            }
          }
          this.targetLayout = newLayout;
        });
      }
    }
    unmount() {
      this.options.layoutId && this.willUpdate();
      this.root.nodes.remove(this);
      const stack = this.getStack();
      stack && stack.remove(this);
      this.parent && this.parent.children.delete(this);
      this.instance = void 0;
      this.eventHandlers.clear();
      cancelFrame(this.updateProjection);
    }
    // only on the root
    blockUpdate() {
      this.updateManuallyBlocked = true;
    }
    unblockUpdate() {
      this.updateManuallyBlocked = false;
    }
    isUpdateBlocked() {
      return this.updateManuallyBlocked || this.updateBlockedByResize;
    }
    isTreeAnimationBlocked() {
      return this.isAnimationBlocked || this.parent && this.parent.isTreeAnimationBlocked() || false;
    }
    // Note: currently only running on root node
    startUpdate() {
      if (this.isUpdateBlocked())
        return;
      this.isUpdating = true;
      this.nodes && this.nodes.forEach(resetSkewAndRotation);
      this.animationId++;
    }
    getTransformTemplate() {
      const { visualElement } = this.options;
      return visualElement && visualElement.getProps().transformTemplate;
    }
    willUpdate(shouldNotifyListeners = true) {
      this.root.hasTreeAnimated = true;
      if (this.root.isUpdateBlocked()) {
        this.options.onExitComplete && this.options.onExitComplete();
        return;
      }
      if (window.MotionCancelOptimisedAnimation && !this.hasCheckedOptimisedAppear) {
        cancelTreeOptimisedTransformAnimations(this);
      }
      !this.root.isUpdating && this.root.startUpdate();
      if (this.isLayoutDirty)
        return;
      this.isLayoutDirty = true;
      for (let i = 0; i < this.path.length; i++) {
        const node = this.path[i];
        node.shouldResetTransform = true;
        if (typeof node.latestValues.x === "string" || typeof node.latestValues.y === "string") {
          node.isLayoutDirty = true;
        }
        node.updateScroll("snapshot");
        if (node.options.layoutRoot) {
          node.willUpdate(false);
        }
      }
      const { layoutId, layout } = this.options;
      if (layoutId === void 0 && !layout)
        return;
      const transformTemplate = this.getTransformTemplate();
      this.prevTransformTemplateValue = transformTemplate ? transformTemplate(this.latestValues, "") : void 0;
      this.updateSnapshot();
      shouldNotifyListeners && this.notifyListeners("willUpdate");
    }
    update() {
      this.updateScheduled = false;
      const updateWasBlocked = this.isUpdateBlocked();
      if (updateWasBlocked) {
        const wasBlockedByResize = this.updateBlockedByResize;
        this.unblockUpdate();
        this.updateBlockedByResize = false;
        this.clearAllSnapshots();
        if (wasBlockedByResize) {
          this.nodes.forEach(forceLayoutMeasure);
        }
        this.nodes.forEach(clearMeasurements);
        return;
      }
      if (this.animationId <= this.animationCommitId) {
        this.nodes.forEach(clearIsLayoutDirty);
        return;
      }
      this.animationCommitId = this.animationId;
      if (!this.isUpdating) {
        this.nodes.forEach(clearIsLayoutDirty);
      } else {
        this.isUpdating = false;
        this.nodes.forEach(ensureDraggedNodesSnapshotted);
        this.nodes.forEach(resetTransformStyle);
        this.nodes.forEach(updateLayout);
        this.nodes.forEach(notifyLayoutUpdate);
      }
      this.clearAllSnapshots();
      const now2 = time.now();
      frameData.delta = clamp(0, 1e3 / 60, now2 - frameData.timestamp);
      frameData.timestamp = now2;
      frameData.isProcessing = true;
      frameSteps.update.process(frameData);
      frameSteps.preRender.process(frameData);
      frameSteps.render.process(frameData);
      frameData.isProcessing = false;
    }
    didUpdate() {
      if (!this.updateScheduled) {
        this.updateScheduled = true;
        microtask.read(this.scheduleUpdate);
      }
    }
    clearAllSnapshots() {
      this.nodes.forEach(clearSnapshot);
      this.sharedNodes.forEach(removeLeadSnapshots);
    }
    scheduleUpdateProjection() {
      if (!this.projectionUpdateScheduled) {
        this.projectionUpdateScheduled = true;
        frame.preRender(this.updateProjection, false, true);
      }
    }
    scheduleCheckAfterUnmount() {
      frame.postRender(() => {
        if (this.isLayoutDirty) {
          this.root.didUpdate();
        } else {
          this.root.checkUpdateFailed();
        }
      });
    }
    /**
     * Update measurements
     */
    updateSnapshot() {
      if (this.snapshot || !this.instance)
        return;
      this.snapshot = this.measure();
      if (this.snapshot && !calcLength(this.snapshot.measuredBox.x) && !calcLength(this.snapshot.measuredBox.y)) {
        this.snapshot = void 0;
      }
    }
    updateLayout() {
      if (!this.instance)
        return;
      this.updateScroll();
      if (!(this.options.alwaysMeasureLayout && this.isLead()) && !this.isLayoutDirty) {
        return;
      }
      if (this.resumeFrom && !this.resumeFrom.instance) {
        for (let i = 0; i < this.path.length; i++) {
          const node = this.path[i];
          node.updateScroll();
        }
      }
      const prevLayout = this.layout;
      this.layout = this.measure(false);
      this.layoutVersion++;
      if (!this.layoutCorrected)
        this.layoutCorrected = createBox();
      this.isLayoutDirty = false;
      this.projectionDelta = void 0;
      this.notifyListeners("measure", this.layout.layoutBox);
      const { visualElement } = this.options;
      visualElement && visualElement.notify("LayoutMeasure", this.layout.layoutBox, prevLayout ? prevLayout.layoutBox : void 0);
    }
    updateScroll(phase = "measure") {
      let needsMeasurement = Boolean(this.options.layoutScroll && this.instance);
      if (this.scroll && this.scroll.animationId === this.root.animationId && this.scroll.phase === phase) {
        needsMeasurement = false;
      }
      if (needsMeasurement && this.instance) {
        const isRoot = checkIsScrollRoot(this.instance);
        this.scroll = {
          animationId: this.root.animationId,
          phase,
          isRoot,
          offset: measureScroll(this.instance),
          wasRoot: this.scroll ? this.scroll.isRoot : isRoot
        };
      }
    }
    resetTransform() {
      if (!resetTransform)
        return;
      const isResetRequested = this.isLayoutDirty || this.shouldResetTransform || this.options.alwaysMeasureLayout;
      const hasProjection = this.projectionDelta && !isDeltaZero(this.projectionDelta);
      const transformTemplate = this.getTransformTemplate();
      const transformTemplateValue = transformTemplate ? transformTemplate(this.latestValues, "") : void 0;
      const transformTemplateHasChanged = transformTemplateValue !== this.prevTransformTemplateValue;
      if (isResetRequested && this.instance && (hasProjection || hasTransform(this.latestValues) || transformTemplateHasChanged)) {
        resetTransform(this.instance, transformTemplateValue);
        this.shouldResetTransform = false;
        this.scheduleRender();
      }
    }
    measure(removeTransform = true) {
      const pageBox = this.measurePageBox();
      let layoutBox = this.removeElementScroll(pageBox);
      if (removeTransform) {
        layoutBox = this.removeTransform(layoutBox);
      }
      roundBox(layoutBox);
      return {
        animationId: this.root.animationId,
        measuredBox: pageBox,
        layoutBox,
        latestValues: {},
        source: this.id
      };
    }
    measurePageBox() {
      const { visualElement } = this.options;
      if (!visualElement)
        return createBox();
      const box = visualElement.measureViewportBox();
      const wasInScrollRoot = this.scroll?.wasRoot || this.path.some(checkNodeWasScrollRoot);
      if (!wasInScrollRoot) {
        const { scroll: scroll2 } = this.root;
        if (scroll2) {
          translateAxis(box.x, scroll2.offset.x);
          translateAxis(box.y, scroll2.offset.y);
        }
      }
      return box;
    }
    removeElementScroll(box) {
      const boxWithoutScroll = createBox();
      copyBoxInto(boxWithoutScroll, box);
      if (this.scroll?.wasRoot) {
        return boxWithoutScroll;
      }
      for (let i = 0; i < this.path.length; i++) {
        const node = this.path[i];
        const { scroll: scroll2, options } = node;
        if (node !== this.root && scroll2 && options.layoutScroll) {
          if (scroll2.wasRoot) {
            copyBoxInto(boxWithoutScroll, box);
          }
          translateAxis(boxWithoutScroll.x, scroll2.offset.x);
          translateAxis(boxWithoutScroll.y, scroll2.offset.y);
        }
      }
      return boxWithoutScroll;
    }
    applyTransform(box, transformOnly = false, output) {
      const withTransforms = output || createBox();
      copyBoxInto(withTransforms, box);
      for (let i = 0; i < this.path.length; i++) {
        const node = this.path[i];
        if (!transformOnly && node.options.layoutScroll && node.scroll && node !== node.root) {
          translateAxis(withTransforms.x, -node.scroll.offset.x);
          translateAxis(withTransforms.y, -node.scroll.offset.y);
        }
        if (!hasTransform(node.latestValues))
          continue;
        transformBox(withTransforms, node.latestValues, node.layout?.layoutBox);
      }
      if (hasTransform(this.latestValues)) {
        transformBox(withTransforms, this.latestValues, this.layout?.layoutBox);
      }
      return withTransforms;
    }
    removeTransform(box) {
      const boxWithoutTransform = createBox();
      copyBoxInto(boxWithoutTransform, box);
      for (let i = 0; i < this.path.length; i++) {
        const node = this.path[i];
        if (!hasTransform(node.latestValues))
          continue;
        let sourceBox;
        if (node.instance) {
          hasScale(node.latestValues) && node.updateSnapshot();
          sourceBox = createBox();
          copyBoxInto(sourceBox, node.measurePageBox());
        }
        removeBoxTransforms(boxWithoutTransform, node.latestValues, node.snapshot?.layoutBox, sourceBox);
      }
      if (hasTransform(this.latestValues)) {
        removeBoxTransforms(boxWithoutTransform, this.latestValues);
      }
      return boxWithoutTransform;
    }
    setTargetDelta(delta) {
      this.targetDelta = delta;
      this.root.scheduleUpdateProjection();
      this.isProjectionDirty = true;
    }
    setOptions(options) {
      this.options = {
        ...this.options,
        ...options,
        crossfade: options.crossfade !== void 0 ? options.crossfade : true
      };
    }
    clearMeasurements() {
      this.scroll = void 0;
      this.layout = void 0;
      this.snapshot = void 0;
      this.prevTransformTemplateValue = void 0;
      this.targetDelta = void 0;
      this.target = void 0;
      this.isLayoutDirty = false;
    }
    forceRelativeParentToResolveTarget() {
      if (!this.relativeParent)
        return;
      if (this.relativeParent.resolvedRelativeTargetAt !== frameData.timestamp) {
        this.relativeParent.resolveTargetDelta(true);
      }
    }
    resolveTargetDelta(forceRecalculation = false) {
      const lead = this.getLead();
      this.isProjectionDirty || (this.isProjectionDirty = lead.isProjectionDirty);
      this.isTransformDirty || (this.isTransformDirty = lead.isTransformDirty);
      this.isSharedProjectionDirty || (this.isSharedProjectionDirty = lead.isSharedProjectionDirty);
      const isShared = Boolean(this.resumingFrom) || this !== lead;
      const canSkip = !(forceRecalculation || isShared && this.isSharedProjectionDirty || this.isProjectionDirty || this.parent?.isProjectionDirty || this.attemptToResolveRelativeTarget || this.root.updateBlockedByResize);
      if (canSkip)
        return;
      const { layout, layoutId } = this.options;
      if (!this.layout || !(layout || layoutId))
        return;
      this.resolvedRelativeTargetAt = frameData.timestamp;
      const relativeParent = this.getClosestProjectingParent();
      if (relativeParent && this.linkedParentVersion !== relativeParent.layoutVersion && !relativeParent.options.layoutRoot) {
        this.removeRelativeTarget();
      }
      if (!this.targetDelta && !this.relativeTarget) {
        if (this.options.layoutAnchor !== false && relativeParent && relativeParent.layout) {
          this.createRelativeTarget(relativeParent, this.layout.layoutBox, relativeParent.layout.layoutBox);
        } else {
          this.removeRelativeTarget();
        }
      }
      if (!this.relativeTarget && !this.targetDelta)
        return;
      if (!this.target) {
        this.target = createBox();
        this.targetWithTransforms = createBox();
      }
      if (this.relativeTarget && this.relativeTargetOrigin && this.relativeParent && this.relativeParent.target) {
        this.forceRelativeParentToResolveTarget();
        calcRelativeBox(this.target, this.relativeTarget, this.relativeParent.target, this.options.layoutAnchor || void 0);
      } else if (this.targetDelta) {
        if (Boolean(this.resumingFrom)) {
          this.applyTransform(this.layout.layoutBox, false, this.target);
        } else {
          copyBoxInto(this.target, this.layout.layoutBox);
        }
        applyBoxDelta(this.target, this.targetDelta);
      } else {
        copyBoxInto(this.target, this.layout.layoutBox);
      }
      if (this.attemptToResolveRelativeTarget) {
        this.attemptToResolveRelativeTarget = false;
        if (this.options.layoutAnchor !== false && relativeParent && Boolean(relativeParent.resumingFrom) === Boolean(this.resumingFrom) && !relativeParent.options.layoutScroll && relativeParent.target && this.animationProgress !== 1) {
          this.createRelativeTarget(relativeParent, this.target, relativeParent.target);
        } else {
          this.relativeParent = this.relativeTarget = void 0;
        }
      }
      if (statsBuffer.value) {
        metrics.calculatedTargetDeltas++;
      }
    }
    getClosestProjectingParent() {
      if (!this.parent || hasScale(this.parent.latestValues) || has2DTranslate(this.parent.latestValues)) {
        return void 0;
      }
      if (this.parent.isProjecting()) {
        return this.parent;
      } else {
        return this.parent.getClosestProjectingParent();
      }
    }
    isProjecting() {
      return Boolean((this.relativeTarget || this.targetDelta || this.options.layoutRoot) && this.layout);
    }
    createRelativeTarget(relativeParent, layout, parentLayout) {
      this.relativeParent = relativeParent;
      this.linkedParentVersion = relativeParent.layoutVersion;
      this.forceRelativeParentToResolveTarget();
      this.relativeTarget = createBox();
      this.relativeTargetOrigin = createBox();
      calcRelativePosition(this.relativeTargetOrigin, layout, parentLayout, this.options.layoutAnchor || void 0);
      copyBoxInto(this.relativeTarget, this.relativeTargetOrigin);
    }
    removeRelativeTarget() {
      this.relativeParent = this.relativeTarget = void 0;
    }
    calcProjection() {
      const lead = this.getLead();
      const isShared = Boolean(this.resumingFrom) || this !== lead;
      let canSkip = true;
      if (this.isProjectionDirty || this.parent?.isProjectionDirty) {
        canSkip = false;
      }
      if (isShared && (this.isSharedProjectionDirty || this.isTransformDirty)) {
        canSkip = false;
      }
      if (this.resolvedRelativeTargetAt === frameData.timestamp) {
        canSkip = false;
      }
      if (canSkip)
        return;
      const { layout, layoutId } = this.options;
      this.isTreeAnimating = Boolean(this.parent && this.parent.isTreeAnimating || this.currentAnimation || this.pendingAnimation);
      if (!this.isTreeAnimating) {
        this.targetDelta = this.relativeTarget = void 0;
      }
      if (!this.layout || !(layout || layoutId))
        return;
      copyBoxInto(this.layoutCorrected, this.layout.layoutBox);
      const prevTreeScaleX = this.treeScale.x;
      const prevTreeScaleY = this.treeScale.y;
      applyTreeDeltas(this.layoutCorrected, this.treeScale, this.path, isShared);
      if (lead.layout && !lead.target && (this.treeScale.x !== 1 || this.treeScale.y !== 1)) {
        lead.target = lead.layout.layoutBox;
        lead.targetWithTransforms = createBox();
      }
      const { target } = lead;
      if (!target) {
        if (this.prevProjectionDelta) {
          this.createProjectionDeltas();
          this.scheduleRender();
        }
        return;
      }
      if (!this.projectionDelta || !this.prevProjectionDelta) {
        this.createProjectionDeltas();
      } else {
        copyAxisDeltaInto(this.prevProjectionDelta.x, this.projectionDelta.x);
        copyAxisDeltaInto(this.prevProjectionDelta.y, this.projectionDelta.y);
      }
      calcBoxDelta(this.projectionDelta, this.layoutCorrected, target, this.latestValues);
      if (this.treeScale.x !== prevTreeScaleX || this.treeScale.y !== prevTreeScaleY || !axisDeltaEquals(this.projectionDelta.x, this.prevProjectionDelta.x) || !axisDeltaEquals(this.projectionDelta.y, this.prevProjectionDelta.y)) {
        this.hasProjected = true;
        this.scheduleRender();
        this.notifyListeners("projectionUpdate", target);
      }
      if (statsBuffer.value) {
        metrics.calculatedProjections++;
      }
    }
    hide() {
      this.isVisible = false;
    }
    show() {
      this.isVisible = true;
    }
    scheduleRender(notifyAll2 = true) {
      this.options.visualElement?.scheduleRender();
      if (notifyAll2) {
        const stack = this.getStack();
        stack && stack.scheduleRender();
      }
      if (this.resumingFrom && !this.resumingFrom.instance) {
        this.resumingFrom = void 0;
      }
    }
    createProjectionDeltas() {
      this.prevProjectionDelta = createDelta();
      this.projectionDelta = createDelta();
      this.projectionDeltaWithTransform = createDelta();
    }
    setAnimationOrigin(delta, hasOnlyRelativeTargetChanged = false, pathFn) {
      const snapshot = this.snapshot;
      const snapshotLatestValues = snapshot ? snapshot.latestValues : {};
      const mixedValues = { ...this.latestValues };
      const targetDelta = createDelta();
      if (!this.relativeParent || !this.relativeParent.options.layoutRoot) {
        this.relativeTarget = this.relativeTargetOrigin = void 0;
      }
      this.attemptToResolveRelativeTarget = !hasOnlyRelativeTargetChanged;
      const relativeLayout = createBox();
      const snapshotSource = snapshot ? snapshot.source : void 0;
      const layoutSource = this.layout ? this.layout.source : void 0;
      const isSharedLayoutAnimation = snapshotSource !== layoutSource;
      const stack = this.getStack();
      const isOnlyMember = !stack || stack.members.length <= 1;
      const shouldCrossfadeOpacity = Boolean(isSharedLayoutAnimation && !isOnlyMember && this.options.crossfade === true && !this.path.some(hasOpacityCrossfade));
      this.animationProgress = 0;
      let prevRelativeTarget;
      const interpolate2 = pathFn?.interpolateProjection(delta);
      this.mixTargetDelta = (latest) => {
        const progress2 = latest / 1e3;
        const point2 = interpolate2?.(progress2);
        if (point2) {
          targetDelta.x.translate = point2.x;
          targetDelta.x.scale = mixNumber(delta.x.scale, 1, progress2);
          targetDelta.x.origin = delta.x.origin;
          targetDelta.x.originPoint = delta.x.originPoint;
          targetDelta.y.translate = point2.y;
          targetDelta.y.scale = mixNumber(delta.y.scale, 1, progress2);
          targetDelta.y.origin = delta.y.origin;
          targetDelta.y.originPoint = delta.y.originPoint;
        } else {
          mixAxisDeltaLinear(targetDelta.x, delta.x, progress2);
          mixAxisDeltaLinear(targetDelta.y, delta.y, progress2);
        }
        this.setTargetDelta(targetDelta);
        if (this.relativeTarget && this.relativeTargetOrigin && this.layout && this.relativeParent && this.relativeParent.layout) {
          calcRelativePosition(relativeLayout, this.layout.layoutBox, this.relativeParent.layout.layoutBox, this.options.layoutAnchor || void 0);
          mixBox(this.relativeTarget, this.relativeTargetOrigin, relativeLayout, progress2);
          if (prevRelativeTarget && boxEquals(this.relativeTarget, prevRelativeTarget)) {
            this.isProjectionDirty = false;
          }
          if (!prevRelativeTarget)
            prevRelativeTarget = createBox();
          copyBoxInto(prevRelativeTarget, this.relativeTarget);
        }
        if (isSharedLayoutAnimation) {
          this.animationValues = mixedValues;
          mixValues(mixedValues, snapshotLatestValues, this.latestValues, progress2, shouldCrossfadeOpacity, isOnlyMember);
        }
        if (point2 && point2.rotate !== void 0) {
          if (!this.animationValues)
            this.animationValues = mixedValues;
          this.animationValues.pathRotation = point2.rotate;
        }
        this.root.scheduleUpdateProjection();
        this.scheduleRender();
        this.animationProgress = progress2;
      };
      this.mixTargetDelta(this.options.layoutRoot ? 1e3 : 0);
    }
    startAnimation(options) {
      this.notifyListeners("animationStart");
      this.currentAnimation?.stop();
      this.resumingFrom?.currentAnimation?.stop();
      if (this.pendingAnimation) {
        cancelFrame(this.pendingAnimation);
        this.pendingAnimation = void 0;
      }
      this.pendingAnimation = frame.update(() => {
        globalProjectionState.hasAnimatedSinceResize = true;
        this.motionValue || (this.motionValue = motionValue(0));
        this.motionValue.jump(0, false);
        this.currentAnimation = animateSingleValue(this.motionValue, [0, 1e3], {
          ...options,
          velocity: 0,
          isSync: true,
          onUpdate: (latest) => {
            this.mixTargetDelta(latest);
            options.onUpdate && options.onUpdate(latest);
          },
          onComplete: () => {
            options.onComplete && options.onComplete();
            this.completeAnimation();
          }
        });
        if (this.resumingFrom) {
          this.resumingFrom.currentAnimation = this.currentAnimation;
        }
        this.pendingAnimation = void 0;
      });
    }
    completeAnimation() {
      if (this.resumingFrom) {
        this.resumingFrom.currentAnimation = void 0;
        this.resumingFrom.preserveOpacity = void 0;
      }
      const stack = this.getStack();
      stack && stack.exitAnimationComplete();
      this.resumingFrom = this.currentAnimation = this.animationValues = void 0;
      this.notifyListeners("animationComplete");
    }
    finishAnimation() {
      if (this.currentAnimation) {
        this.mixTargetDelta && this.mixTargetDelta(animationTarget);
        this.currentAnimation.stop();
      }
      this.completeAnimation();
    }
    applyTransformsToTarget() {
      const lead = this.getLead();
      let { targetWithTransforms, target, layout, latestValues } = lead;
      if (!targetWithTransforms || !target || !layout)
        return;
      if (this !== lead && this.layout && layout && shouldAnimatePositionOnly(this.options.animationType, this.layout.layoutBox, layout.layoutBox)) {
        target = this.target || createBox();
        const xLength = calcLength(this.layout.layoutBox.x);
        target.x.min = lead.target.x.min;
        target.x.max = target.x.min + xLength;
        const yLength = calcLength(this.layout.layoutBox.y);
        target.y.min = lead.target.y.min;
        target.y.max = target.y.min + yLength;
      }
      copyBoxInto(targetWithTransforms, target);
      transformBox(targetWithTransforms, latestValues);
      calcBoxDelta(this.projectionDeltaWithTransform, this.layoutCorrected, targetWithTransforms, latestValues);
    }
    registerSharedNode(layoutId, node) {
      if (!this.sharedNodes.has(layoutId)) {
        this.sharedNodes.set(layoutId, new NodeStack());
      }
      const stack = this.sharedNodes.get(layoutId);
      stack.add(node);
      const config = node.options.initialPromotionConfig;
      node.promote({
        transition: config ? config.transition : void 0,
        preserveFollowOpacity: config && config.shouldPreserveFollowOpacity ? config.shouldPreserveFollowOpacity(node) : void 0
      });
    }
    isLead() {
      const stack = this.getStack();
      return stack ? stack.lead === this : true;
    }
    getLead() {
      const { layoutId } = this.options;
      return layoutId ? this.getStack()?.lead || this : this;
    }
    getPrevLead() {
      const { layoutId } = this.options;
      return layoutId ? this.getStack()?.prevLead : void 0;
    }
    getStack() {
      const { layoutId } = this.options;
      if (layoutId)
        return this.root.sharedNodes.get(layoutId);
    }
    promote({ needsReset, transition, preserveFollowOpacity } = {}) {
      const stack = this.getStack();
      if (stack)
        stack.promote(this, preserveFollowOpacity);
      if (needsReset) {
        this.projectionDelta = void 0;
        this.needsReset = true;
      }
      if (transition)
        this.setOptions({ transition });
    }
    relegate() {
      const stack = this.getStack();
      if (stack) {
        return stack.relegate(this);
      } else {
        return false;
      }
    }
    resetSkewAndRotation() {
      const { visualElement } = this.options;
      if (!visualElement)
        return;
      let hasDistortingTransform = false;
      const { latestValues } = visualElement;
      if (latestValues.z || latestValues.rotate || latestValues.rotateX || latestValues.rotateY || latestValues.rotateZ || latestValues.skewX || latestValues.skewY) {
        hasDistortingTransform = true;
      }
      if (!hasDistortingTransform)
        return;
      const resetValues = {};
      if (latestValues.z) {
        resetDistortingTransform("z", visualElement, resetValues, this.animationValues);
      }
      for (let i = 0; i < transformAxes.length; i++) {
        resetDistortingTransform(`rotate${transformAxes[i]}`, visualElement, resetValues, this.animationValues);
        resetDistortingTransform(`skew${transformAxes[i]}`, visualElement, resetValues, this.animationValues);
      }
      visualElement.render();
      for (const key in resetValues) {
        visualElement.setStaticValue(key, resetValues[key]);
        if (this.animationValues) {
          this.animationValues[key] = resetValues[key];
        }
      }
      visualElement.scheduleRender();
    }
    applyProjectionStyles(targetStyle, styleProp) {
      if (!this.instance || this.isSVG)
        return;
      if (!this.isVisible) {
        targetStyle.visibility = "hidden";
        return;
      }
      const transformTemplate = this.getTransformTemplate();
      if (this.needsReset) {
        this.needsReset = false;
        targetStyle.visibility = "";
        targetStyle.opacity = "";
        targetStyle.pointerEvents = resolveMotionValue(styleProp?.pointerEvents) || "";
        targetStyle.transform = transformTemplate ? transformTemplate(this.latestValues, "") : "none";
        return;
      }
      const lead = this.getLead();
      if (!this.projectionDelta || !this.layout || !lead.target) {
        if (this.options.layoutId) {
          targetStyle.opacity = this.latestValues.opacity !== void 0 ? this.latestValues.opacity : 1;
          targetStyle.pointerEvents = resolveMotionValue(styleProp?.pointerEvents) || "";
        }
        if (this.hasProjected && !hasTransform(this.latestValues)) {
          targetStyle.transform = transformTemplate ? transformTemplate({}, "") : "none";
          this.hasProjected = false;
        }
        return;
      }
      targetStyle.visibility = "";
      const valuesToRender = lead.animationValues || lead.latestValues;
      this.applyTransformsToTarget();
      let transform = buildProjectionTransform(this.projectionDeltaWithTransform, this.treeScale, valuesToRender);
      if (transformTemplate) {
        transform = transformTemplate(valuesToRender, transform);
      }
      targetStyle.transform = transform;
      const { x, y } = this.projectionDelta;
      targetStyle.transformOrigin = `${x.origin * 100}% ${y.origin * 100}% 0`;
      if (lead.animationValues) {
        targetStyle.opacity = lead === this ? valuesToRender.opacity ?? this.latestValues.opacity ?? 1 : this.preserveOpacity ? this.latestValues.opacity : valuesToRender.opacityExit;
      } else {
        targetStyle.opacity = lead === this ? valuesToRender.opacity !== void 0 ? valuesToRender.opacity : "" : valuesToRender.opacityExit !== void 0 ? valuesToRender.opacityExit : 0;
      }
      for (const key in scaleCorrectors) {
        if (valuesToRender[key] === void 0)
          continue;
        const { correct, applyTo, isCSSVariable } = scaleCorrectors[key];
        const corrected = transform === "none" ? valuesToRender[key] : correct(valuesToRender[key], lead);
        if (applyTo) {
          const num2 = applyTo.length;
          for (let i = 0; i < num2; i++) {
            targetStyle[applyTo[i]] = corrected;
          }
        } else {
          if (isCSSVariable) {
            this.options.visualElement.renderState.vars[key] = corrected;
          } else {
            targetStyle[key] = corrected;
          }
        }
      }
      if (this.options.layoutId) {
        targetStyle.pointerEvents = lead === this ? resolveMotionValue(styleProp?.pointerEvents) || "" : "none";
      }
    }
    clearSnapshot() {
      this.resumeFrom = this.snapshot = void 0;
    }
    // Only run on root
    resetTree() {
      this.root.nodes.forEach((node) => node.currentAnimation?.stop());
      this.root.nodes.forEach(clearMeasurements);
      this.root.sharedNodes.clear();
    }
  };
}
function updateLayout(node) {
  node.updateLayout();
}
function notifyLayoutUpdate(node) {
  const snapshot = node.resumeFrom?.snapshot || node.snapshot;
  if (node.isLead() && node.layout && snapshot && node.hasListeners("didUpdate")) {
    const { layoutBox: layout, measuredBox: measuredLayout } = node.layout;
    const { animationType } = node.options;
    const isShared = snapshot.source !== node.layout.source;
    if (animationType === "size") {
      eachAxis((axis) => {
        const axisSnapshot = isShared ? snapshot.measuredBox[axis] : snapshot.layoutBox[axis];
        const length = calcLength(axisSnapshot);
        axisSnapshot.min = layout[axis].min;
        axisSnapshot.max = axisSnapshot.min + length;
      });
    } else if (animationType === "x" || animationType === "y") {
      const snapAxis = animationType === "x" ? "y" : "x";
      copyAxisInto(isShared ? snapshot.measuredBox[snapAxis] : snapshot.layoutBox[snapAxis], layout[snapAxis]);
    } else if (shouldAnimatePositionOnly(animationType, snapshot.layoutBox, layout)) {
      eachAxis((axis) => {
        const axisSnapshot = isShared ? snapshot.measuredBox[axis] : snapshot.layoutBox[axis];
        const length = calcLength(layout[axis]);
        axisSnapshot.max = axisSnapshot.min + length;
        if (node.relativeTarget && !node.currentAnimation) {
          node.isProjectionDirty = true;
          node.relativeTarget[axis].max = node.relativeTarget[axis].min + length;
        }
      });
    }
    const layoutDelta = createDelta();
    calcBoxDelta(layoutDelta, layout, snapshot.layoutBox);
    const visualDelta = createDelta();
    if (isShared) {
      calcBoxDelta(visualDelta, node.applyTransform(measuredLayout, true), snapshot.measuredBox);
    } else {
      calcBoxDelta(visualDelta, layout, snapshot.layoutBox);
    }
    const hasLayoutChanged = !isDeltaZero(layoutDelta);
    let hasRelativeLayoutChanged = false;
    if (!node.resumeFrom) {
      const relativeParent = node.getClosestProjectingParent();
      if (relativeParent && !relativeParent.resumeFrom) {
        const { snapshot: parentSnapshot, layout: parentLayout } = relativeParent;
        if (parentSnapshot && parentLayout) {
          const anchor = node.options.layoutAnchor || void 0;
          const relativeSnapshot = createBox();
          calcRelativePosition(relativeSnapshot, snapshot.layoutBox, parentSnapshot.layoutBox, anchor);
          const relativeLayout = createBox();
          calcRelativePosition(relativeLayout, layout, parentLayout.layoutBox, anchor);
          if (!boxEqualsRounded(relativeSnapshot, relativeLayout)) {
            hasRelativeLayoutChanged = true;
          }
          if (relativeParent.options.layoutRoot) {
            node.relativeTarget = relativeLayout;
            node.relativeTargetOrigin = relativeSnapshot;
            node.relativeParent = relativeParent;
          }
        }
      }
    }
    node.notifyListeners("didUpdate", {
      layout,
      snapshot,
      delta: visualDelta,
      layoutDelta,
      hasLayoutChanged,
      hasRelativeLayoutChanged
    });
  } else if (node.isLead()) {
    const { onExitComplete } = node.options;
    onExitComplete && onExitComplete();
  }
  node.options.transition = void 0;
}
function propagateDirtyNodes(node) {
  if (statsBuffer.value) {
    metrics.nodes++;
  }
  if (!node.parent)
    return;
  if (!node.isProjecting()) {
    node.isProjectionDirty = node.parent.isProjectionDirty;
  }
  node.isSharedProjectionDirty || (node.isSharedProjectionDirty = Boolean(node.isProjectionDirty || node.parent.isProjectionDirty || node.parent.isSharedProjectionDirty));
  node.isTransformDirty || (node.isTransformDirty = node.parent.isTransformDirty);
}
function cleanDirtyNodes(node) {
  node.isProjectionDirty = node.isSharedProjectionDirty = node.isTransformDirty = false;
}
function clearSnapshot(node) {
  node.clearSnapshot();
}
function clearMeasurements(node) {
  node.clearMeasurements();
}
function forceLayoutMeasure(node) {
  node.isLayoutDirty = true;
  node.updateLayout();
}
function clearIsLayoutDirty(node) {
  node.isLayoutDirty = false;
}
function ensureDraggedNodesSnapshotted(node) {
  if (node.isAnimationBlocked && node.layout && !node.isLayoutDirty) {
    node.snapshot = node.layout;
    node.isLayoutDirty = true;
  }
}
function resetTransformStyle(node) {
  const { visualElement } = node.options;
  if (visualElement && visualElement.getProps().onBeforeLayoutMeasure) {
    visualElement.notify("BeforeLayoutMeasure");
  }
  node.resetTransform();
}
function finishAnimation(node) {
  node.finishAnimation();
  node.targetDelta = node.relativeTarget = node.target = void 0;
  node.isProjectionDirty = true;
}
function resolveTargetDelta(node) {
  node.resolveTargetDelta();
}
function calcProjection(node) {
  node.calcProjection();
}
function resetSkewAndRotation(node) {
  node.resetSkewAndRotation();
}
function removeLeadSnapshots(stack) {
  stack.removeLeadSnapshot();
}
function mixAxisDeltaLinear(output, delta, p) {
  output.translate = mixNumber(delta.translate, 0, p);
  output.scale = mixNumber(delta.scale, 1, p);
  output.origin = delta.origin;
  output.originPoint = delta.originPoint;
}
function mixAxis(output, from, to2, p) {
  output.min = mixNumber(from.min, to2.min, p);
  output.max = mixNumber(from.max, to2.max, p);
}
function mixBox(output, from, to2, p) {
  mixAxis(output.x, from.x, to2.x, p);
  mixAxis(output.y, from.y, to2.y, p);
}
function hasOpacityCrossfade(node) {
  return node.animationValues && node.animationValues.opacityExit !== void 0;
}
var defaultLayoutTransition = {
  duration: 0.45,
  ease: [0.4, 0, 0.1, 1]
};
var userAgentContains = (string) => typeof navigator !== "undefined" && navigator.userAgent && navigator.userAgent.toLowerCase().includes(string);
var roundPoint = userAgentContains("applewebkit/") && !userAgentContains("chrome/") ? Math.round : noop;
function roundAxis(axis) {
  axis.min = roundPoint(axis.min);
  axis.max = roundPoint(axis.max);
}
function roundBox(box) {
  roundAxis(box.x);
  roundAxis(box.y);
}
function shouldAnimatePositionOnly(animationType, snapshot, layout) {
  return animationType === "position" || animationType === "preserve-aspect" && !isNear(aspectRatio(snapshot), aspectRatio(layout), 0.2);
}
function checkNodeWasScrollRoot(node) {
  return node !== node.root && node.scroll?.wasRoot;
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/projection/node/DocumentProjectionNode.mjs
var DocumentProjectionNode = createProjectionNode({
  attachResizeListener: (ref, notify2) => addDomEvent(ref, "resize", notify2),
  measureScroll: () => ({
    x: document.documentElement.scrollLeft || document.body?.scrollLeft || 0,
    y: document.documentElement.scrollTop || document.body?.scrollTop || 0
  }),
  checkIsScrollRoot: () => true
});

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/projection/node/group.mjs
var notify = (node) => !node.isLayoutDirty && node.willUpdate(false);
function nodeGroup() {
  const nodes2 = /* @__PURE__ */ new Set();
  const subscriptions = /* @__PURE__ */ new WeakMap();
  const dirtyAll = () => nodes2.forEach(notify);
  return {
    add: (node) => {
      nodes2.add(node);
      subscriptions.set(node, node.addEventListener("willUpdate", dirtyAll));
    },
    remove: (node) => {
      nodes2.delete(node);
      const unsubscribe = subscriptions.get(node);
      if (unsubscribe) {
        unsubscribe();
        subscriptions.delete(node);
      }
      dirtyAll();
    },
    dirty: dirtyAll
  };
}

// ../../node_modules/.pnpm/motion-dom@13.1.1/node_modules/motion-dom/dist/es/projection/node/HTMLProjectionNode.mjs
var rootProjectionNode = {
  current: void 0
};
var HTMLProjectionNode = createProjectionNode({
  measureScroll: (instance) => ({
    x: instance.scrollLeft,
    y: instance.scrollTop
  }),
  defaultParent: () => {
    if (!rootProjectionNode.current) {
      const documentNode = new DocumentProjectionNode({});
      documentNode.mount(window);
      documentNode.setOptions({ layoutScroll: true });
      rootProjectionNode.current = documentNode;
    }
    return rootProjectionNode.current;
  },
  resetTransform: (instance, value) => {
    instance.style.transform = value !== void 0 ? value : "none";
  },
  checkIsScrollRoot: (instance) => Boolean(window.getComputedStyle(instance).position === "fixed")
});

// dist/choreo/easings.js
function easeInAndOut(t) {
  return 0.5 - Math.cos(t * Math.PI) / 2;
}
var adjust = 1 / 2 + 1 / Math.PI;
var cutover = 1 / (2 * adjust);
var intercept = (2 - Math.PI) / 4;
var slope = Math.PI / 2 * adjust;
function easeIn2(t) {
  return t < cutover ? easeInAndOut(t * adjust) : slope * t + intercept;
}
function easeOut2(t) {
  return 1 - easeIn2(1 - t);
}
var quadIn = (t) => t * t;
var quadOut = (t) => 1 - (1 - t) * (1 - t);
var quadInOut = (t) => t < 0.5 ? 2 * t * t : 1 - 2 * (1 - t) * (1 - t);
var EASINGS = Object.freeze({
  expoIn: [0.7, 0, 0.84, 0],
  expoInOut: [0.87, 0, 0.13, 1],
  expoOut: [0.16, 1, 0.3, 1],
  glide: [0.65, 0, 0.35, 1],
  quadIn,
  quadInOut,
  quadOut,
  quartIn: [0.5, 0, 0.75, 0],
  quartInOut: [0.76, 0, 0.24, 1],
  quartOut: [0.25, 1, 0.5, 1],
  quintIn: [0.64, 0, 0.78, 0],
  quintInOut: [0.83, 0, 0.17, 1],
  quintOut: [0.22, 1, 0.36, 1],
  sineIn: [0.12, 0, 0.39, 0],
  sineInOut: [0.37, 0, 0.63, 1],
  sineOut: [0.61, 1, 0.88, 1]
});
var ENGINE = /* @__PURE__ */ new Set(["anticipate", "backIn", "backInOut", "backOut", "circIn", "circInOut", "circOut", "easeIn", "easeInOut", "easeOut", "linear"]);
var isBezier = (e) => e.length > 0 && e.every((n) => typeof n === "number");
function resolveOne(ease3) {
  if (typeof ease3 === "function") {
    return ease3;
  }
  if (typeof ease3 === "string") {
    if (Object.prototype.hasOwnProperty.call(EASINGS, ease3)) {
      return EASINGS[ease3];
    }
    if (ENGINE.has(ease3)) {
      return ease3;
    }
    throw new Error(`choreo: unknown easing '${ease3}' \u2014 use one of ` + [...Object.keys(EASINGS), ...ENGINE].sort().join(", ") + ", a cubic-bezier as four numbers, or a function");
  }
  if (!isBezier(ease3) || ease3.length !== 4) {
    throw new Error(`choreo: a cubic-bezier easing is four numbers; got [${ease3.join(", ")}]`);
  }
  return ease3;
}
function resolveEase(ease3) {
  if (ease3 === void 0) {
    return void 0;
  }
  if (Array.isArray(ease3) && !isBezier(ease3)) {
    return ease3.map(resolveOne);
  }
  return resolveOne(ease3);
}
function easeFunction(ease3) {
  return easingDefinitionToFunction(resolveOne(ease3 ?? "easeInOut"));
}
function zoomEase(from, to2, ease3 = "linear") {
  const e = easeFunction(ease3);
  if (from <= 0 || to2 <= 0) {
    throw new Error("choreo: zoomEase needs two positive zooms");
  }
  if (from === to2) {
    return e;
  }
  const ratio = to2 / from;
  return (t) => (from * Math.pow(ratio, e(t)) - from) / (to2 - from);
}

// dist/choreo/gesture.js
var GESTURE = {
  gesture: true
};
function isGestureRef(v) {
  return typeof v === "object" && v !== null && v.gesture === true;
}
var samples = [];
var tracking = false;
function record(event) {
  const now2 = performance.now();
  samples.push({
    t: now2,
    x: event.clientX,
    y: event.clientY
  });
  if (samples.length > 8) {
    samples.shift();
  }
}
function trackGestures() {
  if (tracking || typeof window === "undefined") {
    return;
  }
  tracking = true;
  window.addEventListener("pointerdown", record, {
    capture: true,
    passive: true
  });
  window.addEventListener("pointermove", record, {
    capture: true,
    passive: true
  });
  window.addEventListener("pointerup", record, {
    capture: true,
    passive: true
  });
}
function gesturePoint() {
  const last = samples[samples.length - 1];
  return last ? {
    x: last.x,
    y: last.y
  } : null;
}
function gestureVelocity() {
  if (samples.length < 2) {
    return {
      x: 0,
      y: 0
    };
  }
  const now2 = performance.now();
  const recent = samples.filter((s) => now2 - s.t < 120);
  const a = recent[0] ?? samples[samples.length - 2];
  const b = samples[samples.length - 1];
  const dt = (b.t - a.t) / 1e3;
  if (dt <= 0) {
    return {
      x: 0,
      y: 0
    };
  }
  return {
    x: (b.x - a.x) / dt,
    y: (b.y - a.y) / dt
  };
}
function gestureBounds(size) {
  const point2 = gesturePoint();
  if (!point2) {
    return null;
  }
  const page = {
    height: size.height,
    width: size.width,
    x: point2.x - size.width / 2,
    y: point2.y - size.height / 2
  };
  return {
    context: page,
    page,
    parent: page
  };
}

// dist/choreo/compile.js
var isBlock = (node) => node.kind === "sequence" || node.kind === "parallel";
var isGate = (node) => node.kind === "gate";
var DEFAULT_SPRING = {
  damping: 30,
  stiffness: 300
};
var DERIVABLE = /* @__PURE__ */ new Set(["filter", "opacity", "rotate", "rotateX", "rotateY", "rotateZ", "scale", "scaleX", "scaleY", "skewX", "skewY", "x", "y", "z"]);
var pathHost;
function samplePath(d, samples2 = 64) {
  if (!pathHost) {
    pathHost = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    pathHost.setAttribute("aria-hidden", "true");
    pathHost.style.cssText = "position:absolute;width:0;height:0;overflow:hidden";
    document.body.appendChild(pathHost);
  }
  const el = document.createElementNS("http://www.w3.org/2000/svg", "path");
  el.setAttribute("d", d);
  pathHost.appendChild(el);
  try {
    const length = el.getTotalLength();
    return Array.from({
      length: samples2 + 1
    }, (_, i) => {
      const pt = el.getPointAtLength(length * i / samples2);
      return {
        x: pt.x,
        y: pt.y
      };
    });
  } finally {
    el.remove();
  }
}
function mapFlight(raw, dx, dy) {
  const s0 = raw[0];
  const e = raw[raw.length - 1];
  const vx = e.x - s0.x;
  const vy = e.y - s0.y;
  const mag = vx * vx + vy * vy;
  if (mag < 1e-6) {
    return raw.map((_, i) => ({
      x: dx * i / (raw.length - 1),
      y: dy * i / (raw.length - 1)
    }));
  }
  const mr = (dx * vx + dy * vy) / mag;
  const mi = (dy * vx - dx * vy) / mag;
  return raw.map((pt) => {
    const px2 = pt.x - s0.x;
    const py = pt.y - s0.y;
    return {
      x: px2 * mr - py * mi,
      y: px2 * mi + py * mr
    };
  });
}
var resolve = (v, sprite, cs) => typeof v === "function" ? v(sprite, cs) : v;
var single = (v) => Array.isArray(v) ? v[0] : v;
var num = (v) => {
  if (typeof v === "number") {
    return v;
  }
  const n = parseFloat(String(v));
  return Number.isNaN(n) ? 0 : n;
};
function currentValue(sprite, key) {
  const ve = sprite.node.visualElement;
  if (ve?.hasValue(key)) {
    return num(ve.getValue(key).get());
  }
  const latest = ve?.latestValues?.[key];
  if (latest !== void 0) {
    return num(latest);
  }
  const computed = getComputedStyle(sprite.element).getPropertyValue(key.startsWith("--") ? key : key.replace(/[A-Z]/g, (m) => "-" + m.toLowerCase()));
  return num(computed);
}
function springDuration(from, to2, spec) {
  if (from === to2) {
    return 0;
  }
  const generator = spring({
    keyframes: [from, to2],
    ...spec
  });
  return Math.min(calcGeneratorDuration(generator), maxGeneratorDuration);
}
function ladder(n, order) {
  const ranks = Array.from({
    length: n
  }, (_, i) => i);
  switch (order) {
    case "reverse":
      return ranks.map((i) => n - 1 - i);
    case "center": {
      const mid = (n - 1) / 2;
      const byDistance = [...ranks].sort((a, b) => Math.abs(a - mid) - Math.abs(b - mid));
      const out = new Array(n);
      byDistance.forEach((index, rank) => out[index] = rank);
      return out;
    }
    case "random": {
      const shuffled = [...ranks];
      for (let i = n - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
      }
      const out = new Array(n);
      shuffled.forEach((index, rank) => out[index] = rank);
      return out;
    }
    default:
      return ranks;
  }
}
function radialRanks(sprites, step, cs) {
  const z = cs.measureZoom ?? 1;
  const centreIn = (b) => b ? {
    x: (b.context.x + b.context.width / 2) / z,
    y: (b.context.y + b.context.height / 2) / z
  } : null;
  const o = step.origin;
  const origin = o === void 0 ? null : isBeaconRef(o) ? centreIn(cs.beacon(o.beacon)) : !Array.isArray(o) && typeof o.x === "number" && typeof o.y === "number" ? o : (() => {
    const s = cs.sprite(o);
    return centreIn(s?.final ?? s?.initial);
  })();
  if (!origin) {
    throw new Error("choreo: @order='radial' needs an @origin it can measure \u2014 a point {x, y}, a sprite, or a beacon that is on the page");
  }
  const rings = step.rings ?? 100;
  const ranks = sprites.map((s) => {
    const c = centreIn(s.final ?? s.initial);
    return c ? Math.round(Math.hypot(c.x - origin.x, c.y - origin.y) / rings) : 0;
  });
  if (step.order === "radial-reverse") {
    const max = Math.max(0, ...ranks);
    return ranks.map((r) => max - r);
  }
  return ranks;
}
function resolveTarget(step, sprite, cs) {
  const target = {};
  let longest = 0;
  for (const key in step.props) {
    const to2 = resolve(step.props[key], sprite, cs);
    if (Array.isArray(to2)) {
      if (step.kind === "spring" && to2.length > 2) {
        throw new Error(`choreo: a spring animates between two keyframes; \`${key}\` was given ${to2.length}`);
      }
      target[key] = to2;
      if (step.kind === "spring") {
        longest = Math.max(longest, springDuration(num(to2[0]), num(to2[to2.length - 1]), step.spring ?? DEFAULT_SPRING));
      }
    } else {
      target[key] = to2;
      if (step.kind === "spring") {
        longest = Math.max(longest, springDuration(currentValue(sprite, key), num(to2), step.spring ?? DEFAULT_SPRING));
      }
    }
  }
  return {
    longest,
    target
  };
}
function matchBoxes(initial, final, from, to2, z) {
  const subI = initial.substance && descale(initial.substance, z);
  const subF = final.substance && descale(final.substance, z);
  if (!subI && !subF) {
    return {
      from,
      to: to2
    };
  }
  const map = (s, a, b) => ({
    height: s.height / (a.height || 1) * b.height,
    width: s.width / (a.width || 1) * b.width,
    x: b.x + (s.x - a.x) / (a.width || 1) * b.width,
    y: b.y + (s.y - a.y) / (a.height || 1) * b.height
  });
  return {
    from: subI ?? map(subF, to2, from),
    to: subF ?? map(subI, from, to2)
  };
}
var centreOf = (r) => ({
  x: r.x + r.width / 2,
  y: r.y + r.height / 2
});
function descale(r, z) {
  return z === 1 ? r : {
    height: r.height / z,
    width: r.width / z,
    x: r.x / z,
    y: r.y / z
  };
}
function resolveMove(step, sprite, cs) {
  const size = (sprite.final ?? sprite.initial)?.page ?? {
    height: 0,
    width: 0
  };
  const hot = step.from && isGestureRef(step.from);
  const borrowedFrom = step.from ? hot ? gestureBounds(size) : cs.beacon(step.from.beacon) : null;
  const borrowedTo = step.to ? cs.beacon(step.to.beacon) : null;
  const initial = borrowedFrom ?? sprite.initial;
  const final = borrowedTo ?? sprite.final;
  if (!initial || !final) {
    return null;
  }
  const z = cs.measureZoom ?? 1;
  const parentSpace = step.space === "parent" && !borrowedFrom && !borrowedTo;
  const from = descale(parentSpace ? initial.parent : initial.page, z);
  const to2 = descale(parentSpace ? final.parent : final.page, z);
  const target = {};
  const pairs = [];
  const scaleMode = step.size === "scale" || step.size === "crop";
  const cropMode = step.size === "crop";
  const m = scaleMode ? matchBoxes(initial, final, from, to2, z) : null;
  const dx = m ? centreOf(m.to).x - centreOf(m.from).x : to2.x - from.x;
  const dy = m ? cropMode ? m.to.y - m.from.y : centreOf(m.to).y - centreOf(m.from).y : to2.y - from.y;
  const holdsStart = sprite.type === "removed";
  const leg = (d) => holdsStart ? [0, d] : [-d, 0];
  let flight;
  if (step.path && (dx !== 0 || dy !== 0)) {
    flight = {
      points: mapFlight(samplePath(step.path), dx, dy),
      rest: holdsStart ? {
        x: 0,
        y: 0
      } : {
        x: dx,
        y: dy
      },
      rotate: step.rotate
    };
    pairs.push(leg(Math.hypot(dx, dy)));
  } else if (m) {
    const crop = cropMode;
    const rx = m.from.width / (m.to.width || 1) || 1;
    const ry = m.from.height / (m.to.height || 1) || 1;
    const su = rx;
    const sx = crop ? su : rx;
    const sy = crop ? su : ry;
    const fx = holdsStart ? 1 / sx : sx;
    const fy = holdsStart ? 1 / sy : sy;
    const anchor = centreOf(holdsStart ? from : to2);
    const matched = holdsStart ? m.from : m.to;
    const pinned = crop ? {
      x: centreOf(matched).x,
      y: matched.y
    } : centreOf(matched);
    const cx = (1 - fx) * (pinned.x - anchor.x);
    const cy = (1 - fy) * (pinned.y - anchor.y);
    const x = holdsStart ? dx + cx : -dx + cx;
    const y = holdsStart ? dy + cy : -dy + cy;
    if (x !== 0) {
      target["x"] = holdsStart ? [0, x] : [x, 0];
      pairs.push(holdsStart ? [0, x] : [x, 0]);
    }
    if (y !== 0) {
      target["y"] = holdsStart ? [0, y] : [y, 0];
      pairs.push(holdsStart ? [0, y] : [y, 0]);
    }
    if (crop) {
      if (fx !== 1) {
        target["scale"] = holdsStart ? [1, fx] : [fx, 1];
      }
      const frame2 = holdsStart ? from : to2;
      const window2 = holdsStart ? m.to : m.from;
      const f = holdsStart ? fx : sx;
      const d = {
        y
      };
      const pre = (edge) => anchor.y + (edge - anchor.y - d.y) / f;
      const clamp2 = (v) => Math.max(0, v);
      const b = clamp2(frame2.y + frame2.height - pre(window2.y + window2.height));
      if (b > 0.5) {
        const far = `inset(0px 0px ${b.toFixed(2)}px 0px)`;
        const rest = "inset(0px 0px 0px 0px)";
        target["clipPath"] = holdsStart ? [rest, far] : [far, rest];
      }
    } else {
      if (fx !== 1) {
        target["scaleX"] = holdsStart ? [1, fx] : [fx, 1];
      }
      if (fy !== 1) {
        target["scaleY"] = holdsStart ? [1, fy] : [fy, 1];
      }
    }
  } else {
    if (dx !== 0) {
      target["x"] = leg(dx);
      pairs.push(leg(dx));
    }
    if (dy !== 0) {
      target["y"] = leg(dy);
      pairs.push(leg(dy));
    }
  }
  if (scaleMode) ;
  else if (step.size !== false) {
    if (from.width !== to2.width) {
      target["width"] = [from.width, to2.width];
      pairs.push([from.width, to2.width]);
    }
    if (from.height !== to2.height) {
      target["height"] = [from.height, to2.height];
      pairs.push([from.height, to2.height]);
    }
  }
  if (!pairs.length) {
    return null;
  }
  let longest = step.ms ?? 0;
  if (step.ms === void 0) {
    const spec = step.spring ?? DEFAULT_SPRING;
    for (const [a, b] of pairs) {
      longest = Math.max(longest, springDuration(a, b, spec));
    }
  }
  return {
    flight,
    longest,
    target,
    // a hot start leaves at the speed it was thrown (§6.1)
    velocity: hot ? gestureVelocity() : void 0
  };
}
function rgbOf(css2) {
  if (!css2) {
    return null;
  }
  const m = /^rgba?\(([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?\)$/.exec(css2);
  if (!m) {
    return null;
  }
  return {
    a: m[4] === void 0 ? 1 : parseFloat(m[4]),
    b: parseFloat(m[3]),
    g: parseFloat(m[2]),
    r: parseFloat(m[1])
  };
}
function effective(paint, ground) {
  const src = rgbOf(paint);
  if (!src || src.a === 0) {
    return null;
  }
  if (src.a === 1) {
    return `rgb(${src.r}, ${src.g}, ${src.b})`;
  }
  const dst = rgbOf(ground);
  if (!dst) {
    return null;
  }
  const mix2 = (s, d) => Math.round(s * src.a + d * (1 - src.a));
  return `rgb(${mix2(src.r, dst.r)}, ${mix2(src.g, dst.g)}, ${mix2(src.b, dst.b)})`;
}
function oneEase(ease3, what) {
  const resolved = resolveEase(ease3);
  if (Array.isArray(resolved) && typeof resolved[0] !== "number") {
    throw new Error(`choreo: ${what} takes one easing \u2014 an array of easings is per keyframe segment, and only a c.Tween has segments`);
  }
  return resolved ?? "easeInOut";
}
var tweenTransition = (step, ms) => ({
  duration: ms / 1e3,
  ease: step.kind === "move" ? oneEase(step.ease, "c.Move") : resolveEase(step.ease) ?? "easeInOut",
  type: "tween"
});
function shapeCheck(step, target, splitting) {
  const {
    times
  } = step;
  const segmented = Array.isArray(step.ease) && typeof step.ease[0] !== "number";
  if (!times && !segmented) {
    return;
  }
  if (splitting) {
    throw new Error("choreo: @times and an @ease array are not supported for text delivery (@by) \u2014 every slot plays the one curve");
  }
  if (times) {
    const ordered = times.every((v, i) => i === 0 || v >= times[i - 1]);
    if (times.length < 2 || times[0] !== 0 || times[times.length - 1] !== 1 || !ordered) {
      throw new Error(`choreo: @times must run from 0 to 1 without going back; got [${times.join(", ")}]`);
    }
  }
  for (const key in target) {
    const frames2 = target[key];
    if (!Array.isArray(frames2)) {
      continue;
    }
    if (times && frames2.length !== times.length) {
      throw new Error(`choreo: @times has ${times.length} offsets but \`${key}\` has ${frames2.length} keyframes \u2014 one offset per keyframe`);
    }
    if (segmented && step.ease.length !== frames2.length - 1) {
      throw new Error(`choreo: @ease has ${step.ease.length} easings but \`${key}\` has ${frames2.length - 1} segments \u2014 one easing per segment`);
    }
  }
}
var springTransition = (spec) => ({
  ...spec ?? DEFAULT_SPRING,
  type: "spring"
});
function resolveStep(step, cs, exclude) {
  const sprites = cs.sprites(step.of ?? {}).filter((s) => !exclude || !exclude.has(s));
  const delay2 = step.delay ?? 0;
  const cues2 = [];
  const stagger2 = step.stagger ?? 0;
  const splitting = (step.kind === "tween" || step.kind === "spring") && step.by !== void 0 && step.by !== "item";
  const order = step.kind === "tween" || step.kind === "spring" ? step.order ?? "forward" : "forward";
  const radial = order === "radial" || order === "radial-reverse";
  if (radial && splitting) {
    throw new Error("choreo: @order='radial' ranks sprites by their resting boxes \u2014 a text split (@by) has none; ripple whole sprites instead");
  }
  const ranks = splitting ? [] : radial ? radialRanks(sprites, step, cs) : ladder(sprites.length, order);
  let longest = 0;
  let open = false;
  for (const [index, sprite] of sprites.entries()) {
    if ((step.kind === "camera" || step.kind === "camera3d" || step.kind === "tether" || step.of === void 0) && index > 0) {
      break;
    }
    const offset = splitting ? 0 : stagger2 * (ranks[index] ?? index);
    switch (step.kind) {
      case "tween": {
        const {
          target
        } = resolveTarget(step, sprite, cs);
        shapeCheck(step, target, splitting);
        if (Object.keys(target).length) {
          const loop = step.repeat === Infinity;
          const plays = loop ? 1 : 1 + (step.repeat ?? 0);
          const length = step.ms * plays;
          const transition = tweenTransition(step, step.ms);
          if (step.repeat) {
            transition["repeat"] = step.repeat;
            transition["repeatType"] = step.repeatType ?? "loop";
          }
          if (step.times) {
            transition["times"] = step.times;
          }
          cues2.push({
            delivery: splitting ? {
              by: step.by,
              order,
              stagger: stagger2
            } : void 0,
            duration: length,
            kind: "tween",
            loop: loop || void 0,
            offset,
            sprite,
            target,
            transition
          });
          longest = Math.max(longest, offset + (loop ? step.ms : length));
        }
        break;
      }
      case "spring": {
        const {
          target,
          longest: d
        } = resolveTarget(step, sprite, cs);
        if (Object.keys(target).length) {
          cues2.push({
            delivery: splitting ? {
              by: step.by,
              order,
              stagger: stagger2
            } : void 0,
            duration: d,
            kind: "spring",
            offset,
            sprite,
            target,
            transition: springTransition(step.spring)
          });
          longest = Math.max(longest, offset + d);
        }
        break;
      }
      case "move": {
        const r = resolveMove(step, sprite, cs);
        if (r) {
          const transition = step.ms === void 0 ? springTransition(step.spring) : tweenTransition(step, step.ms);
          if (r.velocity && step.ms === void 0) {
            if (r.target["x"]) {
              transition["x"] = {
                ...transition,
                velocity: r.velocity.x
              };
            }
            if (r.target["y"]) {
              transition["y"] = {
                ...transition,
                velocity: r.velocity.y
              };
            }
          }
          cues2.push({
            duration: r.longest,
            flight: r.flight,
            kind: "move",
            offset,
            sprite,
            target: r.target,
            transition
          });
          longest = Math.max(longest, offset + r.longest);
          const cp = sprite.counterpart;
          const swap = step.swap ?? "during";
          if (cp && !cp.sent && swap !== "none" && sprite.final && cp.initial) {
            const cpz = cs.measureZoom ?? 1;
            const from = descale(cp.initial.page, cpz);
            const to2 = descale(sprite.final.page, cpz);
            const cpTarget = {};
            if (step.size === "scale" || step.size === "crop") {
              const crop = step.size === "crop";
              const cpm = matchBoxes(cp.initial, sprite.final, from, to2, cpz);
              const mf = centreOf(cpm.from);
              const mt = centreOf(cpm.to);
              const anchor = centreOf(from);
              const rx = cpm.to.width / (cpm.from.width || 1) || 1;
              const ry = cpm.to.height / (cpm.from.height || 1) || 1;
              const eu = rx;
              const ex = crop ? eu : rx;
              const ey = crop ? eu : ry;
              const dxe = mt.x - anchor.x - ex * (mf.x - anchor.x);
              const dye = crop ? cpm.to.y - anchor.y - ey * (cpm.from.y - anchor.y) : mt.y - anchor.y - ey * (mf.y - anchor.y);
              if (dxe !== 0) {
                cpTarget["x"] = [0, dxe];
              }
              if (dye !== 0) {
                cpTarget["y"] = [0, dye];
              }
              if (crop) {
                if (ex !== 1) {
                  cpTarget["scale"] = [1, ex];
                }
                const pre = (edge) => anchor.y + (edge - anchor.y - dye) / ex;
                const clamp2 = (v) => Math.max(0, v);
                const cb = clamp2(from.y + from.height - pre(cpm.to.y + cpm.to.height));
                if (cb > 0.5) {
                  cpTarget["clipPath"] = ["inset(0px 0px 0px 0px)", `inset(0px 0px ${cb.toFixed(2)}px 0px)`];
                }
              } else {
                if (ex !== 1) {
                  cpTarget["scaleX"] = [1, ex];
                }
                if (ey !== 1) {
                  cpTarget["scaleY"] = [1, ey];
                }
              }
            } else {
              if (to2.x !== from.x) {
                cpTarget["x"] = [0, to2.x - from.x];
              }
              if (to2.y !== from.y) {
                cpTarget["y"] = [0, to2.y - from.y];
              }
              if (step.size !== false) {
                if (from.width !== to2.width) {
                  cpTarget["width"] = [from.width, to2.width];
                }
                if (from.height !== to2.height) {
                  cpTarget["height"] = [from.height, to2.height];
                }
              }
            }
            if (Object.keys(cpTarget).length) {
              cues2.push({
                duration: r.longest,
                kind: "move",
                offset,
                sprite: cp,
                target: cpTarget,
                transition
              });
            }
            if (swap === "during") {
              const oldSkin = effective(cp.initial?.paint, cs.ground);
              const newSkin = effective(sprite.final?.paint, cs.ground);
              const fade = {
                duration: r.longest / 1e3,
                ease: "easeInOut"
              };
              if (oldSkin && newSkin) {
                cues2.push({
                  borrow: true,
                  duration: r.longest,
                  kind: "tween",
                  offset,
                  sprite,
                  target: {
                    backgroundColor: [oldSkin, newSkin]
                  },
                  transition: fade
                });
                cues2.push({
                  duration: r.longest,
                  hold: {
                    fill: false,
                    values: {
                      zIndex: 3
                    }
                  },
                  kind: "hold",
                  offset,
                  sprite: cp
                });
              } else {
                cues2.push({
                  duration: r.longest,
                  kind: "tween",
                  offset,
                  sprite,
                  target: {
                    opacity: [0, 1]
                  },
                  transition: fade
                });
              }
              cues2.push({
                duration: r.longest,
                kind: "tween",
                offset,
                sprite: cp,
                target: {
                  opacity: [1, 0]
                },
                transition: fade
              });
            } else {
              cues2.push({
                duration: r.longest,
                hold: {
                  fill: false,
                  values: {
                    opacity: 0
                  }
                },
                kind: "hold",
                offset,
                sprite
              });
            }
          }
        }
        break;
      }
      case "hold": {
        const values = {};
        for (const key in step.props) {
          values[key] = single(resolve(step.props[key], sprite, cs));
        }
        cues2.push({
          duration: step.ms ?? 0,
          hold: {
            fill: step.fill ?? false,
            values
          },
          kind: "hold",
          offset,
          sprite
        });
        if (step.ms === void 0) {
          open = true;
        } else {
          longest = Math.max(longest, offset + step.ms);
        }
        break;
      }
      case "camera": {
        const ms = step.ms ?? 600;
        const fitting = step.fit !== void 0;
        const aiming = step.aim !== void 0;
        const aimQuery = fitting ? step.fit : step.aim ?? step.origin;
        const originSprite = aimQuery ? cs.sprite(aimQuery) : null;
        const box = originSprite?.final?.context ?? originSprite?.initial?.context;
        const oz = cs.measureZoom ?? 1;
        const origin = box ? {
          x: (box.x + box.width / 2) / oz,
          y: (box.y + box.height / 2) / oz
        } : void 0;
        let to2 = {
          x: step.x,
          y: step.y,
          zoom: step.zoom
        };
        const by = step.panBy || step.zoomBy !== void 0 ? {
          x: step.panBy?.x,
          y: step.panBy?.y,
          zoom: step.zoomBy
        } : void 0;
        if (aiming && !fitting) {
          to2 = box && origin && cs.frame ? {
            x: cs.frame.width / 2 - origin.x,
            y: cs.frame.height / 2 - origin.y,
            zoom: void 0
          } : {
            x: 0,
            y: 0,
            zoom: 1
          };
        }
        if (fitting) {
          if (box && origin && cs.frame) {
            const zoom = step.zoom ?? (step.margin ?? 0.72) * Math.min(cs.frame.width * oz / box.width, cs.frame.height * oz / box.height);
            to2 = {
              x: cs.frame.width / 2 - origin.x,
              y: cs.frame.height / 2 - origin.y,
              zoom
            };
          } else {
            to2 = {
              x: 0,
              y: 0,
              zoom: 1
            };
          }
        }
        cues2.push({
          camera: {
            by,
            // centre and origin from the SAME final layout: the aim term
            // (origin − centre) is frozen numbers the run lerps — a board
            // that reflows mid-cue cannot move the camera
            centre: cs.frame ? {
              x: cs.frame.width / 2,
              y: cs.frame.height / 2
            } : void 0,
            origin,
            steady: step.steady ? cs.sprites(step.steady) : [],
            to: to2
          },
          duration: ms,
          kind: "camera",
          offset,
          sprite,
          transition: step.spring ? springTransition(step.spring) : {
            duration: ms / 1e3,
            ease: oneEase(step.ease, "c.Camera")
          }
        });
        longest = Math.max(longest, offset + ms);
        break;
      }
      case "camera3d": {
        const ms = step.ms ?? 600;
        cues2.push({
          camera3d: {
            by: step.by,
            tension: step.tension,
            through: step.through,
            to: {
              dolly: step.dolly,
              look: step.look,
              pitch: step.pitch,
              x: step.x,
              y: step.y,
              yaw: step.yaw
            }
          },
          duration: ms,
          kind: "camera3d",
          offset,
          sprite,
          transition: step.spring ? springTransition(step.spring) : {
            duration: ms / 1e3,
            ease: oneEase(step.ease, "c.Camera3D")
          }
        });
        longest = Math.max(longest, offset + ms);
        break;
      }
      case "tether": {
        cues2.push({
          duration: step.ms ?? 0,
          kind: "tether",
          offset,
          sprite,
          tether: {
            from: cs.sprites(step.from)[0] ?? null,
            name: step.name,
            path: step.path,
            to: cs.sprites(step.to)[0] ?? null
          }
        });
        if (step.ms === void 0) {
          open = true;
        } else {
          longest = Math.max(longest, offset + step.ms);
        }
        break;
      }
      case "follow": {
        for (const key of Object.keys(step.rest)) {
          if (!DERIVABLE.has(key)) {
            throw new Error(`choreo: c.Follow cannot drive '${key}' \u2014 a derived value is computed every frame, so it may only write transform, opacity and filter properties, never layout`);
          }
        }
        const fz = cs.measureZoom ?? 1;
        const inZ = (r) => ({
          height: r.height / fz,
          width: r.width / fz,
          x: r.x / fz,
          y: r.y / fz
        });
        const restBounds = sprite.final ?? sprite.initial;
        if (!restBounds) {
          break;
        }
        const followed = [];
        for (const source of step.to ? cs.sprites(step.to) : []) {
          const toB = source.final ?? source.initial;
          const fromB = source.initial ?? source.final;
          if (toB && fromB) {
            followed.push({
              from: inZ(fromB.context),
              sprite: source,
              to: inZ(toB.context)
            });
          }
        }
        const ms = step.ms;
        cues2.push({
          derive: {
            read: step.read,
            rest: step.rest,
            restBox: inZ(restBounds.context),
            sources: followed
          },
          duration: ms ?? 0,
          kind: "follow",
          offset,
          sprite
        });
        if (ms === void 0) {
          open = true;
        } else {
          longest = Math.max(longest, offset + ms);
        }
        break;
      }
      case "scroll": {
        const ms = step.ms ?? 420;
        cues2.push({
          duration: ms,
          kind: "scroll",
          offset,
          scroll: {
            align: step.align ?? "center"
          },
          sprite
        });
        longest = Math.max(longest, offset + ms);
        break;
      }
      case "raise": {
        cues2.push({
          duration: step.ms ?? 0,
          kind: "raise",
          offset,
          raise: {
            shadow: step.shadow ?? false
          },
          sprite
        });
        if (step.ms === void 0) {
          open = true;
        } else {
          longest = Math.max(longest, offset + step.ms);
        }
        break;
      }
      case "attach":
        cues2.push({
          attach: {
            end: step.end ?? "hold",
            exact: step.exact ?? false,
            in: step.in ?? 0,
            rate: step.rate ?? 1,
            region: step.region
          },
          duration: step.ms,
          kind: "attach",
          offset,
          sprite
        });
        longest = Math.max(longest, offset + step.ms);
        break;
      case "wait":
        cues2.push({
          duration: step.ms,
          kind: "wait",
          offset,
          sprite
        });
        longest = Math.max(longest, offset + step.ms);
        break;
      case "perform":
        cues2.push({
          duration: 0,
          kind: "perform",
          offset,
          perform: {
            action: step.action,
            payload: step.payload,
            target: step.target
          },
          sprite
        });
        longest = Math.max(longest, offset);
        break;
    }
  }
  return {
    cues: cues2,
    duration: cues2.length ? delay2 + longest : 0,
    open
  };
}
function compile(tree, cs) {
  const explicit = /* @__PURE__ */ new Set();
  const claim = (node) => {
    if (isGate(node)) {
      return;
    }
    if (isBlock(node)) {
      node.children.forEach(claim);
      return;
    }
    if (node.generic || node.kind !== "tween" && node.kind !== "spring" && node.kind !== "move" && node.kind !== "hold") {
      return;
    }
    const q = node.of;
    const selective = Array.isArray(q) ? q.length > 0 : q.id !== void 0 || q.role !== void 0 || q.type !== void 0;
    if (!selective) {
      return;
    }
    for (const s of cs.sprites(q)) {
      explicit.add(s);
    }
  };
  tree.forEach(claim);
  const resolved = /* @__PURE__ */ new Map();
  const of = (step) => {
    let r = resolved.get(step);
    if (!r) {
      r = resolveStep(step, cs, step.generic ? explicit : void 0);
      resolved.set(step, r);
    }
    return r;
  };
  const extent = (node) => {
    if (isGate(node)) {
      return 0;
    }
    if (!isBlock(node)) {
      return of(node).duration;
    }
    return node.kind === "sequence" ? node.children.reduce((sum, c) => sum + measure3(c), 0) : node.children.reduce((max, c) => Math.max(max, measure3(c)), 0);
  };
  const measure3 = (node) => {
    if (isGate(node)) {
      return 0;
    }
    if (node.at) {
      return 0;
    }
    return isBlock(node) ? (node.delay ?? 0) + extent(node) : of(node).duration;
  };
  const out = [];
  const seen = /* @__PURE__ */ new Set();
  const checkNames = (node) => {
    if (isGate(node)) {
      return;
    }
    if (node.name) {
      if (seen.has(node.name)) {
        throw new Error(`choreo: two steps named '${node.name}'`);
      }
      seen.add(node.name);
    }
    if (isBlock(node)) {
      node.children.forEach(checkNames);
    }
  };
  tree.forEach(checkNames);
  const names = /* @__PURE__ */ new Map();
  const gates = [];
  const forbidGates = (node) => {
    if (isGate(node)) {
      throw new Error("choreo: a gate inside a parallel has no meaning \u2014 a pause is a total order; only an uncontained sequence can hold one");
    }
    if (isBlock(node)) {
      node.children.forEach(forbidGates);
    }
  };
  const root = measure3({
    children: tree,
    kind: "parallel"
  });
  const standingScore = root === 0;
  let stood = false;
  const place = (node, start2, span) => {
    if (isGate(node)) {
      gates.push({
        at: start2,
        auto: node.ms
      });
      return;
    }
    const anchored = (ref) => {
      const target = names.get(ref.anchor);
      if (!target) {
        throw new Error(`choreo: @at names '${ref.anchor}', which is not a step above this one \u2014 anchors point up the score`);
      }
      return ref.edge === "end" ? target.start + target.duration + (ref.delay ?? 0) * 1e3 : target.start + (ref.progress ?? 0) * target.duration;
    };
    if (!isBlock(node)) {
      const r = of(node);
      const delay2 = node.delay ?? 0;
      let base = start2;
      if (node.at) {
        if (r.open) {
          throw new Error("choreo: an anchored hold needs its own @duration \u2014 lifted out of its block, it has no span to borrow");
        }
        base = anchored(node.at);
      }
      if (node.name) {
        names.set(node.name, {
          duration: Math.max(0, r.duration - delay2),
          start: base + delay2
        });
      }
      for (const cue of r.cues) {
        const {
          offset,
          ...rest
        } = cue;
        const borrows = r.open && (cue.kind === "hold" || cue.kind === "raise" || cue.kind === "tether" || cue.kind === "follow");
        if (borrows && standingScore) {
          stood = true;
        }
        out.push({
          ...rest,
          duration: borrows ? standingScore ? Infinity : Math.max(0, span - delay2 - offset) : cue.duration,
          standing: borrows && standingScore ? true : void 0,
          start: base + delay2 + offset
        });
      }
      return;
    }
    const total = extent(node);
    const from = (node.at ? anchored(node.at) : start2) + (node.delay ?? 0);
    if (node.name) {
      names.set(node.name, {
        duration: total,
        start: from
      });
    }
    if (node.kind === "sequence") {
      let offset = 0;
      for (const child of node.children) {
        place(child, from + offset, total - offset);
        offset += measure3(child);
      }
      return;
    }
    node.children.forEach(forbidGates);
    for (const child of node.children) {
      place(child, from, total);
    }
  };
  if (tree.length > 1) {
    tree.forEach(forbidGates);
  }
  for (const node of tree) {
    place(node, 0, root);
  }
  gates.sort((a, b) => a.at - b.at);
  const derived = out.filter((cue) => cue.derive);
  if (!derived.length) {
    return {
      cues: out,
      gates,
      open: stood
    };
  }
  const nameOf = (sprite) => sprite.id ?? sprite.role ?? "a sprite";
  const drivenBy = /* @__PURE__ */ new Map();
  for (const cue of derived) {
    drivenBy.set(cue.sprite, cue);
  }
  for (const cue of derived) {
    for (const source of cue.derive.sources) {
      if (drivenBy.has(source.sprite)) {
        throw new Error(`choreo: c.Follow on '${nameOf(cue.sprite)}' reads '${nameOf(source.sprite)}', which is itself derived \u2014 a follower may not follow a follower`);
      }
    }
  }
  return {
    cues: [...out.filter((cue) => !cue.derive), ...derived],
    gates,
    open: stood
  };
}
function continuation(sprite, cs, inherited) {
  const step = {
    size: "scale"
  };
  const r = resolveMove(step, sprite, cs);
  if (!r) {
    return null;
  }
  const springy = inherited && (inherited["type"] === "spring" || "stiffness" in inherited || "visualDuration" in inherited || "bounce" in inherited);
  return {
    duration: r.longest,
    flight: r.flight,
    kind: "move",
    sprite,
    start: 0,
    target: r.target,
    transition: springy ? inherited : springTransition(void 0)
  };
}
function sameScore(a, b) {
  return a.length === b.length && a.every((cue, i) => sameCue(cue, b[i]));
}
function sameCue(a, b) {
  if (a.kind !== b.kind || a.sprite.node !== b.sprite.node || a.start !== b.start || a.duration !== b.duration || (a.loop ?? false) !== (b.loop ?? false)) {
    return false;
  }
  if (a.flight || b.flight) {
    return false;
  }
  if (a.tether || b.tether) {
    if (!a.tether || !b.tether || a.tether.from?.node !== b.tether.from?.node || a.tether.to?.node !== b.tether.to?.node || a.tether.path !== b.tether.path || a.tether.name !== b.tether.name) {
      return false;
    }
  }
  if (a.raise || b.raise) {
    if (!a.raise || !b.raise || a.raise.shadow !== b.raise.shadow) {
      return false;
    }
  }
  if (a.attach || b.attach) {
    if (!a.attach || !b.attach || a.attach.region !== b.attach.region || a.attach.in !== b.attach.in || a.attach.rate !== b.attach.rate || a.attach.end !== b.attach.end) {
      return false;
    }
  }
  if (a.scroll || b.scroll) {
    if (!a.scroll || !b.scroll || a.scroll.align !== b.scroll.align) {
      return false;
    }
  }
  const plain = (v) => JSON.stringify(v ?? null);
  const cam2 = (c) => c ? {
    centre: c.centre ?? null,
    origin: c.origin ?? null,
    steady: c.steady.length,
    to: c.to
  } : null;
  return plain(a.target) === plain(b.target) && plain(a.transition) === plain(b.transition) && plain(a.delivery) === plain(b.delivery) && plain(a.hold) === plain(b.hold) && plain(cam2(a.camera)) === plain(cam2(b.camera)) && // the 3D shot is part of the score, not decoration on it: two cues
  // that agree on everything else and disagree about where the lens
  // goes are different cues, and a run kept across that difference
  // plays the old path under the new film
  plain(a.camera3d) === plain(b.camera3d);
}

// dist/choreo/far.js
var intents = /* @__PURE__ */ new Set();
var booked = false;
var schedule = (fn3) => fn3();
function setPassScheduler(fn3) {
  schedule = fn3;
}
function join(host) {
  intents.add(host);
  if (!booked) {
    booked = true;
    schedule(runBarrier);
  }
}
function leave(host) {
  intents.delete(host);
}
registerBusyProbe(() => booked && "far-match barrier booked");
var beforeMeasure = () => {
};
function setBeforeMeasure(fn3) {
  beforeMeasure = fn3;
}
function runBarrier() {
  booked = false;
  const hosts3 = [...intents];
  intents.clear();
  beforeMeasure();
  const passes = [];
  for (const host of hosts3) {
    const pass = host.measurePass();
    if (pass) {
      passes.push(pass);
    }
  }
  if (passes.length > 1) {
    match(passes);
  }
  for (const pass of passes) {
    pass.host.finishPass(pass);
  }
}
var deltaOf = (s) => s.initial && s.final ? {
  height: s.final.page.height - s.initial.page.height,
  width: s.final.page.width - s.initial.page.width,
  x: s.final.page.x - s.initial.page.x,
  y: s.final.page.y - s.initial.page.y
} : void 0;
function match(passes) {
  for (const pass of passes) {
    for (const s of pass.inserted) {
      if (s.id === null || s.counterpart) {
        continue;
      }
      for (const other of passes) {
        if (other === pass) {
          continue;
        }
        const sender = other.removed.find((r) => r.id === s.id && !r.counterpart && !r.sent);
        if (sender) {
          sender.sent = true;
          s.counterpart = sender;
          s.initial = sender.initial;
          s.type = "kept";
          s.delta = deltaOf(s);
          break;
        }
      }
    }
  }
}

// dist/choreo/registry.js
var hosts = /* @__PURE__ */ new WeakMap();
var hostsById = /* @__PURE__ */ new Map();
function setChoreoHost(el, host) {
  const id2 = el.getAttribute("data-choreo");
  if (host) {
    hosts.set(el, host);
    if (id2) {
      hostsById.set(id2, host);
    }
  } else {
    const mine = hosts.get(el);
    hosts.delete(el);
    if (id2 && mine && hostsById.get(id2) === mine) {
      hostsById.delete(id2);
    }
  }
}
function closestChoreo(el) {
  const root = el.parentElement?.closest("[data-choreo]");
  return root ? hosts.get(root) : void 0;
}
function choreoHostAt(el) {
  return hosts.get(el);
}
function choreoHostById(id2) {
  return hostsById.get(id2);
}

// dist/speed.js
var divisor = 1;
var listeners = /* @__PURE__ */ new Set();
function motionSpeed() {
  return divisor;
}
function setMotionSpeed(next2) {
  const clean2 = Number.isFinite(next2) && next2 > 0 ? next2 : 1;
  if (clean2 === divisor) {
    return;
  }
  divisor = clean2;
  listeners.forEach((fn3) => fn3(clean2));
}
function onMotionSpeed(fn3) {
  listeners.add(fn3);
  return () => listeners.delete(fn3);
}
var TIMES = ["duration", "delay", "visualDuration", "repeatDelay"];
var STAGGERS = ["staggerChildren", "delayChildren"];
var NOT_A_VALUE = /* @__PURE__ */ new Set([...TIMES, ...STAGGERS, "type", "ease", "times", "repeat", "repeatType", "bounce", "stiffness", "damping", "mass", "velocity", "restSpeed", "restDelta", "from", "elapsed", "driver", "onPlay", "onComplete", "onUpdate", "when", "staggerDirection"]);
function scaleSpring(t, k) {
  if (t["stiffness"] !== void 0 || t["damping"] !== void 0) {
    t["mass"] = (t["mass"] ?? 1) * k * k;
    if (t["damping"] !== void 0) {
      t["damping"] = t["damping"] * k;
    }
  }
}
function scaleTransition(transition, k) {
  if (!transition || k === 1 || typeof transition !== "object") {
    return transition;
  }
  const out = {
    ...transition
  };
  for (const key of TIMES) {
    if (typeof out[key] === "number") {
      out[key] = out[key] * k;
    }
  }
  for (const key of STAGGERS) {
    if (typeof out[key] === "number") {
      out[key] = out[key] * k;
    }
  }
  scaleSpring(out, k);
  for (const key of Object.keys(out)) {
    const value = out[key];
    if (!NOT_A_VALUE.has(key) && value && typeof value === "object" && !Array.isArray(value)) {
      out[key] = scaleTransition(value, k);
    }
  }
  return out;
}
var slowed = (transition) => scaleTransition(transition, divisor);

// dist/choreo/deliver.js
var spanFor = (text) => {
  const span = document.createElement("span");
  span.textContent = text;
  span.setAttribute("aria-hidden", "true");
  span.style.display = "inline-block";
  span.style.whiteSpace = "pre";
  return span;
};
function textNodesOf(root) {
  const out = [];
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    if ((n.textContent ?? "").length) {
      out.push(n);
    }
  }
  return out;
}
function unitsOf(text, by) {
  if (by === "character") {
    return Array.from(text);
  }
  return text.match(/\S+\s*|\s+/g) ?? [];
}
function split(el, by) {
  if (by === "paragraph") {
    const slots2 = Array.from(el.children).filter((c) => c instanceof HTMLElement);
    if (!slots2.length) {
      throw new Error("choreo: @by='paragraph' needs child elements to deliver");
    }
    return {
      restore() {
      },
      slots: slots2.map((s) => ({
        el: s
      }))
    };
  }
  const originals = textNodesOf(el);
  if (!originals.length) {
    throw new Error(`choreo: @by='${by}' needs text to deliver`);
  }
  const ws = getComputedStyle(el).whiteSpace;
  const collapsing = ws === "normal" || ws === "nowrap" || ws === "pre-line";
  const textOf = (node, index) => {
    let text = node.textContent ?? "";
    if (collapsing) {
      text = text.replace(/\s+/g, " ");
      if (index === 0) {
        text = text.replace(/^ /, "");
      }
      if (index === originals.length - 1) {
        text = text.replace(/ $/, "");
      }
    }
    return text;
  };
  const label = el.getAttribute("aria-label");
  el.setAttribute("aria-label", el.textContent ?? "");
  const slots = [];
  const undo = [];
  for (const [index, node] of originals.entries()) {
    const parent = node.parentNode;
    const marker = document.createComment("choreo-delivery");
    parent.replaceChild(marker, node);
    const spans = [];
    for (const unit of unitsOf(textOf(node, index), by)) {
      const span = spanFor(unit);
      parent.insertBefore(span, marker);
      spans.push(span);
      if (by === "character" && /^\s+$/.test(unit)) {
        continue;
      }
      slots.push({
        el: span
      });
    }
    undo.push(() => {
      for (const span of spans) {
        span.remove();
      }
      marker.parentNode?.replaceChild(node, marker);
    });
  }
  let restored = false;
  return {
    restore() {
      if (restored) {
        return;
      }
      restored = true;
      undo.reverse().forEach((fn3) => fn3());
      if (label === null) {
        el.removeAttribute("aria-label");
      } else {
        el.setAttribute("aria-label", label);
      }
    },
    slots
  };
}
function windows(n, span, stagger2) {
  if (n <= 1 || span <= 0) {
    return Array.from({
      length: n
    }, () => ({
      at: 0,
      ms: span
    }));
  }
  if (stagger2 > 0) {
    const ms2 = Math.max(1, span - (n - 1) * stagger2);
    return Array.from({
      length: n
    }, (_, i) => ({
      at: i * stagger2,
      ms: ms2
    }));
  }
  const ms = span * 0.55;
  return Array.from({
    length: n
  }, (_, i) => ({
    at: i * (span - ms) / (n - 1),
    ms
  }));
}
var UNITLESS = /* @__PURE__ */ new Set(["opacity", "scale", "scaleX", "scaleY"]);
var TRANSFORMS = {
  rotate: (v) => `rotate(${v}deg)`,
  scale: (v) => `scale(${v})`,
  x: (v) => `translateX(${v}px)`,
  y: (v) => `translateY(${v}px)`
};
function keyframesOf(target) {
  const out = {};
  const transforms = /* @__PURE__ */ new Map();
  for (const key in target) {
    const raw = target[key];
    const values = (Array.isArray(raw) ? raw : [raw]).map(String);
    if (TRANSFORMS[key]) {
      transforms.set(key, values);
    } else {
      out[UNITLESS.has(key) || isNaN(Number(values[0])) ? key : key] = values;
    }
  }
  if (transforms.size) {
    const length = Math.max(...[...transforms.values()].map((v) => v.length));
    const frames2 = [];
    for (let i = 0; i < length; i++) {
      const parts = [];
      for (const [key, values] of transforms) {
        parts.push(TRANSFORMS[key](values[Math.min(i, values.length - 1)]));
      }
      frames2.push(parts.join(" "));
    }
    out["transform"] = frames2;
  }
  return out;
}
var NAMED = {
  // the overshoots as cubic-beziers, so a text delivery may Pop: these are
  // motion's own anticipate/back curves flattened to one bend
  anticipate: "cubic-bezier(0.68,-0.6,0.32,1.6)",
  backIn: "cubic-bezier(0.36,0,0.66,-0.56)",
  backInOut: "cubic-bezier(0.68,-0.6,0.32,1.6)",
  backOut: "cubic-bezier(0.34,1.56,0.64,1)",
  circIn: "cubic-bezier(0.55,0,1,0.45)",
  circInOut: "cubic-bezier(0.85,0,0.15,1)",
  circOut: "cubic-bezier(0,0.55,0.45,1)",
  easeIn: "ease-in",
  easeInOut: "ease-in-out",
  easeOut: "ease-out",
  linear: "linear"
};
function cssEasing(ease3, ms) {
  if (ease3 === void 0) {
    return "ease-in-out";
  }
  if (typeof ease3 === "string") {
    const curve = Object.prototype.hasOwnProperty.call(EASINGS, ease3) ? EASINGS[ease3] : void 0;
    return curve ? cssEasing(curve, ms) : NAMED[ease3] ?? "ease-in-out";
  }
  if (Array.isArray(ease3)) {
    return `cubic-bezier(${ease3.join(",")})`;
  }
  return generateLinearEasing(ease3, ms);
}
function springEasing(spec) {
  const generator = spring({
    keyframes: [0, 100],
    ...spec ?? {}
  });
  const ms = Math.min(calcGeneratorDuration(generator), maxGeneratorDuration);
  const progress2 = (t) => generator.next(t * ms).value / 100;
  return {
    easing: generateLinearEasing(progress2, ms),
    ms
  };
}
function deliver(cue, speed) {
  const {
    by,
    order,
    stagger: stagger2
  } = cue.delivery;
  if (by === "item") {
    throw new Error("choreo: item delivery is the ladder, not a split");
  }
  const parts = split(cue.sprite.element, by);
  const ranks = ladder(parts.slots.length, order);
  const spans = windows(parts.slots.length, cue.duration, stagger2);
  const keyframes2 = keyframesOf(cue.target ?? {});
  const isSpring2 = cue.kind === "spring";
  const sprung = isSpring2 ? springEasing(cue.transition) : void 0;
  const animations = [];
  for (const [index, slot] of parts.slots.entries()) {
    const w = spans[ranks[index] ?? index];
    const ms = sprung ? Math.min(sprung.ms, w.ms) : w.ms;
    animations.push(slot.el.animate(keyframes2, {
      delay: w.at * speed,
      duration: Math.max(1, ms * speed),
      easing: sprung ? sprung.easing : cssEasing(cue.transition?.ease, ms),
      fill: "both"
    }));
  }
  let done = false;
  const land = () => {
    if (done) {
      return;
    }
    done = true;
    const ve = cue.sprite.node.visualElement;
    if (ve && cue.target) {
      for (const key in cue.target) {
        const raw = cue.target[key];
        const end = Array.isArray(raw) ? raw[raw.length - 1] : raw;
        ve.getValue(key, end).jump(end);
      }
      ve.render();
    }
    parts.restore();
  };
  const finished = Promise.all(animations.map((a) => a.finished.catch(() => {
  }))).then(land);
  return {
    cancel() {
      done = true;
      animations.forEach((a) => a.cancel());
      parts.restore();
    },
    complete() {
      animations.forEach((a) => {
        try {
          a.finish();
        } catch {
          a.cancel();
        }
      });
      land();
    },
    finished,
    pause() {
      animations.forEach((a) => a.pause());
    },
    play() {
      animations.forEach((a) => a.play());
    },
    seek(ms) {
      const t = Math.max(0, ms * speed);
      animations.forEach((a) => a.currentTime = t);
    },
    speed(rate) {
      animations.forEach((a) => a.playbackRate = rate);
    }
  };
}

// dist/choreo/run.js
function crVal(p0, p1, p2, p3, u, k, s1 = 1, s2 = 1) {
  const m1 = k * s1 * (p2 - p0);
  const m2 = k * s2 * (p3 - p1);
  const u2 = u * u;
  const u3 = u2 * u;
  return (2 * u3 - 3 * u2 + 1) * p1 + (u3 - 2 * u2 + u) * m1 + (-2 * u3 + 3 * u2) * p2 + (u3 - u2) * m2;
}
function resolveThrough(from, through) {
  const aimed = !!from.look || through.some((w) => w.look);
  const seed = {
    ...from,
    look: aimed ? from.look ?? {
      x: 0,
      y: 0,
      z: 0
    } : void 0
  };
  const pts = [seed];
  let prev = seed;
  for (const w of through) {
    const p = {
      dolly: w.dolly ?? prev.dolly,
      look: aimed ? w.look ?? prev.look : void 0,
      pitch: w.pitch ?? prev.pitch,
      x: w.x ?? prev.x,
      y: w.y ?? prev.y,
      yaw: w.yaw ?? prev.yaw
    };
    pts.push(p);
    prev = p;
  }
  return pts;
}
function sampleThrough(from, through, progress2, tension) {
  return prepareThrough(from, through, tension)(progress2);
}
function prepareThrough(from, through, tension) {
  const k = (1 - (tension ?? 0.5)) / 2;
  const pts = resolveThrough(from, through);
  const T = [0];
  for (const w of through) {
    T.push(T[T.length - 1] + Math.max(1e-6, w.slots ?? 1));
  }
  const end = T[T.length - 1];
  let seams = [];
  for (const [n, w] of through.entries()) {
    if (w.cut) {
      seams.push(n + 1);
    }
  }
  let first = 0;
  if (seams[0] === 1) {
    first = 1;
    seams = seams.slice(1);
  }
  return (progress2) => sampleResolved(pts, T, end, first, seams, k, progress2);
}
function sampleResolved(pts, T, end, first, seams, k, progress2) {
  const s = Math.min(end - 1e-9, Math.max(0, progress2 * end));
  let a = first;
  let e = pts.length;
  let w0 = 0;
  let w1 = end;
  for (const seam of seams) {
    if (s < T[seam]) {
      e = seam;
      w1 = T[seam];
      break;
    }
    a = seam;
    w0 = T[seam];
  }
  const m = e - a;
  const lam = m === 1 ? 0 : Math.max(0, Math.min(1 - 1e-9, (s - w0) / (w1 - w0)));
  const st = T[a] + lam * (T[e - 1] - T[a]);
  let i = a;
  while (i < e - 2 && T[i + 1] <= st) {
    i++;
  }
  const h = m === 1 ? 1 : T[i + 1] - T[i];
  const u = m === 1 ? 0 : Math.max(0, Math.min(1, (st - T[i]) / h));
  const P = (j) => pts[Math.max(a, Math.min(e - 1, j))];
  const K = (j) => j < a ? T[a] - (T[Math.min(e - 1, a + 1)] - T[a]) : j > e - 1 ? T[e - 1] + (T[e - 1] - T[Math.max(a, e - 2)]) : T[j];
  const s1 = 2 * h / Math.max(1e-9, K(i + 1) - K(i - 1));
  const s2 = 2 * h / Math.max(1e-9, K(i + 2) - K(i));
  const p0 = P(i - 1);
  const p1 = P(i);
  const p2 = P(i + 1);
  const p3 = P(i + 2);
  const v = (key) => crVal(p0[key], p1[key], p2[key], p3[key], u, k, s1, s2);
  const out = {
    dolly: v("dolly"),
    pitch: v("pitch"),
    x: v("x"),
    y: v("y"),
    yaw: v("yaw")
  };
  if (p1.look && p2.look) {
    const l = (a2) => crVal((p0.look ?? p1.look)[a2], p1.look[a2], p2.look[a2], (p3.look ?? p2.look)[a2], u, k, s1, s2);
    out.look = {
      x: l("x"),
      y: l("y"),
      z: l("z")
    };
  }
  return out;
}
var MIDFLIGHT_KEYS = ["height", "rotate", "scale", "scaleX", "scaleY", "width", "x", "y"];
function isSpring(transition) {
  if (!transition) {
    return false;
  }
  if (transition["type"]) {
    return transition["type"] === "spring";
  }
  return "bounce" in transition || "damping" in transition || "stiffness" in transition || "visualDuration" in transition;
}
function platformControls(animation) {
  return {
    cancel: () => animation.cancel(),
    pause: () => animation.pause(),
    play: () => animation.play(),
    get speed() {
      return animation.playbackRate;
    },
    set speed(rate) {
      animation.playbackRate = rate;
    },
    get state() {
      return animation.playState;
    },
    stop: () => animation.cancel(),
    get time() {
      return (animation.currentTime ?? 0) / 1e3;
    },
    set time(seconds) {
      animation.currentTime = seconds * 1e3;
    }
  };
}
function carryVelocity(transition, cue, inherit) {
  if (!inherit || !cue.target || !isSpring(transition)) {
    return transition;
  }
  const was = inherit.get(cue.sprite.element) ?? (cue.sprite.counterpart && inherit.get(cue.sprite.counterpart.element));
  if (!was) {
    return transition;
  }
  let out = transition;
  for (const key in cue.target) {
    const velocity = was.get(key);
    if (velocity) {
      if (out === transition) {
        out = {
          ...transition
        };
      }
      out[key] = {
        ...transition,
        velocity
      };
    }
  }
  return out;
}
var dash = (key) => key.startsWith("--") ? key : key.replace(/[A-Z]/g, (m) => "-" + m.toLowerCase());
var noop2 = () => {
};
function playsOf(transition) {
  const repeat = transition?.repeat ?? 0;
  return Number.isFinite(repeat) && repeat > 0 ? 1 + Math.floor(repeat) : 1;
}
function finalOf(cue, key) {
  const raw = cue.target[key];
  if (!Array.isArray(raw)) {
    return raw;
  }
  const transition = cue.transition;
  const back = (transition?.repeatType === "mirror" || transition?.repeatType === "reverse") && playsOf(transition) % 2 === 0;
  return back ? raw[0] : raw[raw.length - 1];
}
function nearest(frames2, p) {
  return frames2[Math.min(frames2.length - 1, Math.floor(p * frames2.length))];
}
function mixed(frames2, ms, duration, transition) {
  const types = new Set(frames2.map((f) => typeof f));
  const values = types.size > 1 ? frames2.map((f) => typeof f === "number" ? f : parseFloat(f)) : frames2;
  const p = duration > 0 ? ms / duration : 1;
  if (values.some((v) => typeof v === "number" && Number.isNaN(v))) {
    return nearest(frames2, p);
  }
  const generator = keyframes({
    duration: Math.max(duration, 1e-6),
    ease: transition?.ease ?? "easeInOut",
    keyframes: values,
    times: transition?.times
  });
  const value = generator.next(duration > 0 ? ms : 1e-6).value;
  return typeof value === "number" && Number.isNaN(value) || typeof value === "string" && value.includes("NaN") ? nearest(frames2, p) : value;
}
var SIZES = {
  height: true,
  width: true
};
function applyHold(ve, el, values) {
  const held = [];
  for (const key in values) {
    const had = ve.hasValue(key);
    const prior = had ? ve.getValue(key).get() : void 0;
    const priorStyle = key.startsWith("--") ? el.style.getPropertyValue(key) : el.style[key] ?? "";
    const mv = ve.getValue(key, values[key]);
    mv.jump(values[key]);
    held.push({
      had,
      key,
      prior,
      priorStyle
    });
  }
  ve.scheduleRender();
  return held;
}
function releaseHold(ve, el, held) {
  for (const {
    had,
    key,
    prior,
    priorStyle
  } of held) {
    if (had) {
      ve.getValue(key)?.jump(prior);
    } else {
      ve.removeValue(key);
      if (priorStyle) {
        el.style.setProperty(dash(key), priorStyle);
      } else {
        el.style.removeProperty(dash(key));
      }
    }
  }
  ve.scheduleRender();
}
var ChoreoRun = class _ChoreoRun {
  cues;
  velocities = /* @__PURE__ */ new Map();
  finished;
  // deliberately untracked: the clock mutates inside render-adjacent
  // computations (the pass barrier, engine frames), where a tracked write
  // after a read is an error. Reactive mirrors can wrap this handle later.
  master = 0;
  playing = true;
  parkedAt = null;
  rate = 1;
  scale = motionSpeed();
  standing;
  total;
  gates;
  tracks = [];
  rowEnd = /* @__PURE__ */ new Map();
  released = /* @__PURE__ */ new Set();
  pending;
  options;
  borrowedValues = [];
  /** rest is what releaseForMeasure jumps to: 0 for translates, 1 for scales, 'none' for clips */
  movedValues = [];
  /** what the last releaseForMeasure retired, so a kept pass can put it back */
  retired = {
    borrowed: [],
    moved: []
  };
  owned = [];
  cancelled = false;
  ended = false;
  resolveFinished;
  ticking = false;
  autoTimer;
  constructor(compiled, options) {
    this.options = options;
    this.camera = options.camera ?? {
      x: 0,
      y: 0,
      zoom: 1
    };
    this.camera3d = options.camera3d ?? {
      dolly: 1,
      pitch: 0,
      x: 0,
      y: 0,
      yaw: 0
    };
    this.initial3d = {
      ...this.camera3d
    };
    this.cameraAim = options.cameraAim ?? null;
    this.initialCamera = {
      ...this.camera
    };
    this.initialAim = this.cameraAim ? {
      ...this.cameraAim
    } : null;
    this.cues = compiled.cues;
    this.pending = new Set(options.removed);
    const s = this.scale;
    this.gates = compiled.gates.map((g) => ({
      at: g.at * s,
      auto: g.auto === void 0 ? void 0 : g.auto * s,
      opened: false
    }));
    this.standing = compiled.open ?? false;
    let total = 0;
    for (const cue of this.cues) {
      const start2 = cue.start * s;
      const duration = cue.duration * s;
      this.tracks.push({
        cue,
        end: start2 + duration,
        passed: false,
        start: start2,
        started: false
      });
      if (!cue.loop && !cue.standing) {
        total = Math.max(total, start2 + duration);
      }
      this.rowEnd.set(cue.sprite, Math.max(this.rowEnd.get(cue.sprite) ?? 0, cue.standing ? start2 : start2 + duration));
    }
    for (const g of this.gates) {
      total = Math.max(total, g.at);
    }
    for (const [sprite, end] of this.rowEnd) {
      if (sprite.counterpart) {
        this.rowEnd.set(sprite.counterpart, Math.max(this.rowEnd.get(sprite.counterpart) ?? 0, end));
      }
    }
    this.total = total;
    this.finished = new Promise((resolve3) => {
      this.resolveFinished = resolve3;
    });
    this.pinStarts();
    this.evaluate();
    this.startTicking();
    activeRuns.add(this);
    void this.finished.then(() => activeRuns.delete(this));
  }
  /* ---- the public face, in seconds at 1× ---- */
  get duration() {
    return this.total / this.scale / 1e3;
  }
  get paused() {
    return !this.playing;
  }
  get time() {
    return this.master / this.scale / 1e3;
  }
  set time(seconds) {
    this.seekTo(seconds * 1e3 * this.scale);
  }
  get speed() {
    return this.rate;
  }
  set speed(rate) {
    this.rate = rate;
    for (const t of this.tracks) {
      t.controls?.forEach((c) => c.speed = rate);
      if (t.delivery) {
        t.delivery.speed(rate);
      }
      if (t.loopAnimation) {
        t.loopAnimation.playbackRate = rate;
      }
      if (t.cameraAnimation) {
        t.cameraAnimation.playbackRate = rate;
      }
    }
  }
  get segment() {
    let n = 0;
    for (const g of this.gates) {
      if (this.master > g.at || this.master === g.at && g.opened) {
        n++;
      }
    }
    return n;
  }
  get parked() {
    return this.parkedAt !== null;
  }
  /**
   * ATTACH: write each attached region's clock from this one's.
   *
   * Several windows may name one region — a film's every beat has a plate
   * window, and the plate is one region re-keyed per beat — so the run
   * resolves ONE governing window per region on every evaluate: the window
   * that holds `now`; else the latest past one, if it holds; else the
   * earliest future one, which stands the child at its head (Remotion's
   * premount: mounted early, clock frozen at `in`). The child's run is
   * paused and told `in + (now − start) × rate`. No history is kept on
   * either side, which is what makes a seek into a window land where
   * playing there would.
   */
  driveAttachments(now2) {
    let governing;
    for (const t of this.tracks) {
      const a = t.cue.attach;
      if (!a || t.refused) {
        continue;
      }
      governing ??= /* @__PURE__ */ new Map();
      const g = governing.get(a.region);
      if (!g) {
        governing.set(a.region, t);
        continue;
      }
      const rank = (x) => now2 >= x.start && now2 < x.end ? 2 : now2 >= x.end ? 1 : 0;
      const rt = rank(t);
      const rg = rank(g);
      if (rt > rg || rt === rg && rt === 1 && t.end > g.end || rt === rg && rt === 0 && t.start < g.start) {
        governing.set(a.region, t);
      }
    }
    if (!governing) {
      return;
    }
    for (const [region, t] of governing) {
      const a = t.cue.attach;
      const child = choreoHostById(region)?.currentRun() ?? null;
      if (!child || child === this) {
        continue;
      }
      if (a.exact && child.hasIntegrator()) {
        t.refused = true;
        console.error(`choreo: <Choreo "${region}"> is attached under an exact clock, but its score integrates (a spring or a follow): its state is its history, and a driven clock has none`);
        continue;
      }
      let local;
      if (now2 < t.start) {
        local = a.in;
      } else if (now2 < t.end) {
        local = a.in + (now2 - t.start) / 1e3 / this.scale * a.rate;
      } else if (a.end === "hold") {
        local = a.in + t.cue.duration / 1e3 * a.rate;
      } else {
        continue;
      }
      const inside = now2 >= t.start && now2 < t.end;
      if (this.playing && inside && !this.ended) {
        if (child.paused) {
          child.time = local;
          child.play();
        } else if (Math.abs(child.time - local) > 1 / 30) {
          child.time = local;
        }
        const speed = this.rate * a.rate;
        if (Math.abs(child.speed - speed) > 1e-6) {
          child.speed = speed;
        }
        continue;
      }
      if (!child.paused) {
        child.pause();
      }
      if (Math.abs(child.time - local) > 1e-4) {
        child.time = local;
      }
    }
  }
  /** does this run's score integrate — a spring, a follow — so that its state is its history? */
  hasIntegrator() {
    return this.tracks.some((t) => t.cue.kind === "spring" || !!t.cue.derive);
  }
  isDone() {
    return this.ended || this.cancelled;
  }
  midflight() {
    const out = /* @__PURE__ */ new Map();
    if (this.isDone()) {
      return out;
    }
    for (const t of this.tracks) {
      const {
        cue
      } = t;
      if (!t.started || t.passed) {
        continue;
      }
      const geometry = cue.flight !== void 0 || cue.target !== void 0 && MIDFLIGHT_KEYS.some((key) => key in cue.target);
      if (geometry) {
        out.set(cue.sprite.node, cue.transition);
      }
    }
    return out;
  }
  /* ---- transport ---- */
  pause() {
    if (!this.playing) {
      return;
    }
    this.playing = false;
    this.setPaused(true);
    this.driveAttachments(this.master);
    this.scheduleRestill();
  }
  play() {
    if (this.playing || this.ended || this.cancelled) {
      return;
    }
    if (this.parkedAt) {
      return;
    }
    this.playing = true;
    this.setPaused(false);
    this.startTicking();
  }
  advance() {
    if (this.ended || this.cancelled) {
      return;
    }
    const gate = this.parkedAt;
    if (gate) {
      gate.opened = true;
      this.parkedAt = null;
      clearTimeout(this.autoTimer);
      this.playing = true;
      this.setPaused(false);
      this.startTicking();
      return;
    }
    const next2 = this.gates.find((g) => !g.opened && g.at >= this.master);
    this.seekTo(next2 ? next2.at : this.total);
    if (!next2 && this.master >= this.total && !this.standing) {
      this.finish();
    }
  }
  retreat() {
    if (this.cancelled) {
      return false;
    }
    const eps = 1e-6;
    const behind = this.gates.filter((g) => g.at < this.master - eps);
    const target = behind[behind.length - 1];
    if (!target) {
      return false;
    }
    clearTimeout(this.autoTimer);
    for (const g of this.gates) {
      if (g.at >= target.at) {
        g.opened = false;
      }
    }
    this.ended = false;
    this.master = Math.max(0, target.at - 0.5);
    this.playing = false;
    this.setPaused(true);
    this.evaluate();
    this.park(target, false);
    return true;
  }
  /* ---- the clock ---- */
  startTicking() {
    if (this.ticking || !this.playing || this.cancelled || this.ended) {
      return;
    }
    this.ticking = true;
    frame.update(this.tick, true);
  }
  stopTicking() {
    if (this.ticking) {
      this.ticking = false;
      cancelFrame(this.tick);
    }
  }
  tick = (data) => {
    if (!this.playing || this.cancelled || this.ended) {
      this.stopTicking();
      return;
    }
    const next2 = this.master + data.delta * this.rate;
    const gate = this.gates.find((g) => !g.opened && g.at >= this.master && g.at <= next2);
    if (gate) {
      this.master = gate.at;
      this.evaluate(gate.at);
      this.park(gate);
      return;
    }
    this.master = next2;
    this.evaluate();
    for (const [sprite, end] of this.rowEnd) {
      if (this.master >= end && !this.released.has(sprite)) {
        this.released.add(sprite);
        if (this.pending.delete(sprite)) {
          this.options.onSpriteDone(sprite);
        }
      }
    }
    if (this.master >= this.total && !this.standing) {
      this.finish();
    }
  };
  park(gate, auto2 = true) {
    gate.opened = false;
    this.parkedAt = gate;
    this.playing = false;
    this.stopTicking();
    if (this.options.doomed) {
      for (const sprite of [...this.pending]) {
        this.pending.delete(sprite);
        this.options.onSpriteDone(sprite);
      }
    }
    for (const t of this.tracks) {
      if (t.started && !t.cue.loop && !t.cue.hold && t.end <= this.master) {
        this.completeTrack(t);
      }
    }
    this.setPaused(true);
    this.scheduleRestill();
    if (auto2 && gate.auto !== void 0) {
      this.autoTimer = setTimeout(() => {
        if (this.parkedAt === gate && !this.cancelled) {
          this.advance();
        }
      }, gate.auto / this.rate);
    }
  }
  finish() {
    if (this.ended) {
      return;
    }
    this.ended = true;
    this.stopTicking();
    this.driveAttachments(this.master);
    this.options.onCamera?.({
      ...this.camera
    });
    for (const t of this.tracks) {
      if (t.started && !t.cue.loop && !t.cue.hold && !t.cue.delivery) {
        this.completeTrack(t);
      }
    }
    this.releaseForMeasure();
    for (const sprite of [...this.pending]) {
      this.pending.delete(sprite);
      this.options.onSpriteDone(sprite);
    }
    this.resolveFinished();
  }
  /* ---- cue lifecycle against the clock ---- */
  setPaused(paused) {
    const now2 = this.master;
    for (const t of this.tracks) {
      if (!t.started) {
        continue;
      }
      const due = now2 >= t.start && (now2 < t.end || t.cue.loop);
      const run = !paused && due;
      t.controls?.forEach((c) => {
        if (run) {
          if (c.state === "running" || c.state === "paused") {
            c.play();
          }
        } else if (c.state === "running") {
          c.pause();
        }
      });
      if (t.delivery) {
        (run ? t.delivery.play : t.delivery.pause)();
      }
      if (t.loopAnimation) {
        if (run) {
          t.loopAnimation.play();
        } else {
          t.loopAnimation.pause();
        }
      }
      if (t.cameraAnimation) {
        if (run) {
          t.cameraAnimation.play();
        } else {
          t.cameraAnimation.pause();
        }
      }
    }
  }
  /** release every leaver whose row has ended by `t` (see RunOptions.releaseOnSeek) */
  releasePast(t) {
    for (const [sprite, end] of this.rowEnd) {
      if (t >= end && !this.released.has(sprite)) {
        this.released.add(sprite);
        if (this.pending.delete(sprite)) {
          this.options.onSpriteDone(sprite);
        }
      }
    }
  }
  seekTo(target) {
    const gate = this.gates.find((g) => !g.opened && g.at >= this.master && g.at <= target);
    const clamped = Math.max(0, Math.min(gate ? gate.at : target, this.total));
    this.master = clamped;
    if (this.ended && clamped < this.total) {
      this.ended = false;
    }
    const wasPlaying = this.playing;
    this.playing = false;
    this.setPaused(true);
    this.reconstructCameraAt(gate ? gate.at : Infinity);
    this.evaluate(gate ? gate.at : Infinity);
    if (this.options.releaseOnSeek) {
      this.releasePast(this.master);
    }
    if (gate) {
      this.park(gate);
      return;
    }
    if (wasPlaying && !this.ended) {
      this.playing = true;
      this.setPaused(false);
      this.startTicking();
      return;
    }
    this.scheduleRestill();
  }
  /**
   * The one cost WAAPI acceleration charges a scrubbable run: a finished
   * accelerated animation commits its finals asynchronously, and that
   * commit can land AFTER a still's jump and overwrite it. So a still is
   * re-asserted on the two frames after it is entered — by then any
   * pending commit has landed, and the computed frame wins again.
   */
  restillPending = 0;
  scheduleRestill() {
    if (this.restillPending > 0) {
      return;
    }
    this.restillPending = 2;
    const pass = () => {
      if (this.playing || this.cancelled) {
        this.restillPending = 0;
        return;
      }
      this.restill();
      this.restillPending -= 1;
      if (this.restillPending > 0) {
        frame.postRender(pass);
      }
    };
    frame.postRender(pass);
  }
  restill() {
    const now2 = this.master;
    const rewinds = [];
    for (const t of this.tracks) {
      const {
        cue
      } = t;
      const ve = cue.sprite.node.visualElement;
      if (!ve || cue.camera || cue.tether) {
        continue;
      }
      if (!t.started && t.origin && now2 < t.start) {
        rewinds.push(t);
      } else if (t.started && !t.controls && !t.delivery && !t.loopAnimation && (cue.target || cue.flight) && now2 >= t.start && now2 < t.end) {
        this.sampleStill(t, now2);
      }
    }
    this.rewind(rewinds, now2);
  }
  evaluate(limit = Infinity) {
    const now2 = this.master;
    const rewinds = [];
    let shot = null;
    for (const t of this.tracks) {
      const {
        cue
      } = t;
      if (t.passed && now2 < t.end) {
        t.passed = false;
        if (now2 < t.start && t.origin) {
          rewinds.push(t);
        }
      }
      const fill = cue.hold?.fill ?? false;
      const inside = now2 >= t.start && t.start < limit && (now2 < t.end || cue.loop || fill);
      if (cue.camera) {
        if (inside && !t.started) {
          t.started = true;
          t.cameraFrom = {
            ...this.camera
          };
          const aimTo = cue.camera.origin ?? this.cameraAim ?? cue.camera.centre ?? {
            x: 0,
            y: 0
          };
          t.aimFrom = this.cameraAim ?? aimTo;
          t.aimTo = aimTo;
          this.cameraAim = aimTo;
          t.cameraTo = _ChoreoRun.resolveCameraTo(cue.camera, t.cameraFrom);
        } else if (!inside && t.started && now2 < t.start) {
          t.started = false;
          t.cameraTo = void 0;
          t.cameraAnimation?.cancel();
          t.cameraAnimation = void 0;
          if (t.cameraFrom) {
            this.camera = {
              ...t.cameraFrom
            };
            this.cameraAim = t.aimFrom ?? null;
            t.cameraP = 0;
            this.applyCamera(t);
          }
        }
        if (t.started && (now2 < t.end || !t.passed)) {
          const p = now2 >= t.end ? 1 : this.cameraProgress(t, now2 - t.start);
          const from = t.cameraFrom;
          const to2 = t.cameraTo ?? _ChoreoRun.resolveCameraTo(cue.camera, from);
          t.cameraP = p;
          this.camera = {
            x: from.x + (to2.x - from.x) * p,
            y: from.y + (to2.y - from.y) * p,
            zoom: from.zoom + (to2.zoom - from.zoom) * p
          };
          if (this.playing && now2 < t.end) {
            if (!t.cameraAnimation) {
              this.startCameraAnimation(t, now2);
            } else if (t.cameraAnimation.playState === "paused") {
              t.cameraAnimation.play();
            }
          } else if (t.cameraAnimation) {
            if (now2 >= t.end) {
              this.dropCameraAnimation(t);
            } else {
              t.cameraAnimation.pause();
              t.cameraAnimation.currentTime = Math.max(0, now2 - t.start);
            }
          }
          this.applyCamera(t);
          if (now2 >= t.end && this.playing && !t.passed) {
            t.passed = true;
            this.options.onCamera?.({
              ...this.camera
            });
          }
        }
        continue;
      }
      if (cue.camera3d) {
        const from = shot ?? {
          ...this.initial3d
        };
        const through = cue.camera3d.through;
        if (through?.length) {
          if (now2 <= t.start) {
            shot = from;
          } else {
            const p = now2 >= t.end ? 1 : this.cameraProgress(t, now2 - t.start);
            shot = sampleThrough(from, through, p, cue.camera3d.tension);
          }
          continue;
        }
        const want = cue.camera3d.to;
        const fromLook = from.look;
        const to2 = cue.camera3d.by ? {
          dolly: from.dolly * (want.dolly ?? 1),
          look: want.look ? {
            x: (fromLook?.x ?? 0) + want.look.x,
            y: (fromLook?.y ?? 0) + want.look.y,
            z: (fromLook?.z ?? 0) + want.look.z
          } : fromLook,
          pitch: from.pitch + (want.pitch ?? 0),
          x: from.x + (want.x ?? 0),
          y: from.y + (want.y ?? 0),
          yaw: from.yaw + (want.yaw ?? 0)
        } : {
          dolly: want.dolly ?? from.dolly,
          look: want.look ?? fromLook,
          pitch: want.pitch ?? from.pitch,
          x: want.x ?? from.x,
          y: want.y ?? from.y,
          yaw: want.yaw ?? from.yaw
        };
        if (now2 <= t.start) {
          shot = from;
        } else {
          const p = now2 >= t.end ? 1 : this.cameraProgress(t, now2 - t.start);
          shot = {
            dolly: from.dolly + (to2.dolly - from.dolly) * p,
            pitch: from.pitch + (to2.pitch - from.pitch) * p,
            x: from.x + (to2.x - from.x) * p,
            y: from.y + (to2.y - from.y) * p,
            yaw: from.yaw + (to2.yaw - from.yaw) * p
          };
          if (to2.look || fromLook) {
            const a = fromLook ?? {
              x: 0,
              y: 0,
              z: 0
            };
            const b = to2.look ?? a;
            shot.look = {
              x: a.x + (b.x - a.x) * p,
              y: a.y + (b.y - a.y) * p,
              z: a.z + (b.z - a.z) * p
            };
          }
        }
        continue;
      }
      if (cue.tether) {
        if (inside && !t.started) {
          t.started = true;
          const layer = this.options.tetherLayer;
          if (layer) {
            t.wire = document.createElementNS("http://www.w3.org/2000/svg", "path");
            t.wire.setAttribute("data-choreo-tether", "");
            if (t.cue.tether?.name) {
              t.wire.setAttribute("data-thread", t.cue.tether.name);
            }
            layer.appendChild(t.wire);
          }
        } else if (!inside && t.started) {
          t.started = false;
          t.wire?.remove();
          t.wire = void 0;
        }
        if (t.started && t.wire) {
          this.scheduleTetherDraw();
        }
        continue;
      }
      if (cue.derive) {
        if (inside && !t.started) {
          t.started = true;
          const ve = cue.sprite.node.visualElement;
          if (ve) {
            for (const [key, rest] of Object.entries(cue.derive.rest)) {
              this.movedValues.push({
                key,
                rest,
                ve
              });
            }
          }
        } else if (!inside && t.started) {
          t.started = false;
          this.restDerived(t);
        }
        if (t.started) {
          this.drive(t, now2);
        }
        continue;
      }
      if (cue.raise) {
        if (inside && !t.started) {
          t.started = true;
          this.promote(t);
        } else if (!inside && t.started) {
          t.started = false;
          this.restore(t);
        }
        continue;
      }
      if (cue.scroll) {
        if (inside && !t.started) {
          t.started = true;
          this.startScroll(t);
        } else if (!inside && t.started && now2 < t.start) {
          t.started = false;
          this.stopScroll(t, true);
        }
        if (t.started && t.scrolling) {
          const p = this.flightlessProgress(t, now2 - t.start);
          const {
            container,
            from,
            to: to2
          } = t.scrolling;
          container.scrollTop = from.top + (to2.top - from.top) * p;
          container.scrollLeft = from.left + (to2.left - from.left) * p;
          if (p >= 1 && this.playing) {
            this.stopScroll(t, false);
          }
        }
        continue;
      }
      if (cue.hold) {
        if (inside && !t.started) {
          t.started = true;
          const ve = cue.sprite.node.visualElement;
          if (ve) {
            t.held = applyHold(ve, cue.sprite.element, cue.hold.values);
          }
        } else if (!inside && t.started) {
          t.started = false;
          const ve = cue.sprite.node.visualElement;
          if (ve && t.held) {
            releaseHold(ve, cue.sprite.element, t.held);
            t.held = void 0;
          }
        }
        continue;
      }
      if (cue.kind === "wait") {
        continue;
      }
      if (inside && !t.started) {
        this.startTrack(t);
      } else if (inside && t.started && this.playing && !t.controls && !t.delivery && !t.loopAnimation && (cue.target || cue.flight)) {
        this.startTrack(t);
      } else if (!inside && t.started && now2 < t.start) {
        t.passed = false;
        t.started = false;
        flushKeyframeResolvers();
        this.stopTrack(t);
        t.delivery?.cancel();
        t.delivery = void 0;
        t.loopAnimation?.cancel();
        t.loopAnimation = void 0;
        if (t.origin) {
          rewinds.push(t);
        }
      } else if (t.started && now2 >= t.end && !cue.loop && !this.playing) {
        this.completeTrack(t);
      } else if (!t.started && !t.passed && now2 >= t.end && !cue.loop) {
        this.jumpFinals(t);
      }
      if (t.started && !this.playing && now2 >= t.start) {
        if (t.delivery) {
          t.delivery.pause();
          t.delivery.seek(now2 - t.start);
        } else if (t.loopAnimation) {
          t.loopAnimation.pause();
          const cycle = t.end - t.start;
          t.loopAnimation.currentTime = cycle ? (now2 - t.start) % cycle : 0;
        } else if (cue.target || cue.flight) {
          if (t.controls) {
            flushKeyframeResolvers();
            this.stopTrack(t);
          }
          this.sampleStill(t, now2);
        }
      }
    }
    if (shot) {
      const was = this.camera3d;
      if (was.yaw !== shot.yaw || was.pitch !== shot.pitch || was.dolly !== shot.dolly || was.x !== shot.x || was.y !== shot.y || was.look?.x !== shot.look?.x || was.look?.y !== shot.look?.y || was.look?.z !== shot.look?.z) {
        this.camera3d = shot;
        this.options.onCamera3D?.({
          ...shot
        });
      }
    }
    this.rewind(rewinds, now2);
    this.driveAttachments(now2);
    this.foldPerforms(limit);
  }
  /** perform tracks whose commands the host currently holds (see foldPerforms) */
  performed = /* @__PURE__ */ new Set();
  /** dispatches queued for after the render pass, in fold order */
  pendingPerforms = [];
  performFlushBooked = false;
  /**
   * The command fold (§C4): the set of Perform cues at or before the
   * clock IS the commanded state. Every evaluate — a play tick and a seek
   * alike — re-derives the eligible set; growth dispatches the new
   * commands in time order, and any shrink (a backward seek) resets the
   * host first and replays the whole remaining prefix. Commands are
   * idempotent statements of state by contract (`lamp.on`, never a
   * toggle), which is exactly what makes the replay a re-derivation.
   *
   * Dispatches are DEFERRED past the render pass: the constructor's first
   * evaluate runs while Glimmer may still be rendering, and a command
   * exists to mutate application state. A reset collapses the queue — the
   * dropped dispatches were never seen, and the replay that follows
   * restates everything still standing.
   */
  foldPerforms(limit) {
    if (!this.options.onPerform && !this.options.onPerformReset) {
      return;
    }
    const now2 = this.master;
    const eligible = this.tracks.filter((t) => t.cue.perform && now2 >= t.start && t.start < limit).sort((a, b) => a.start - b.start);
    const held = new Set(eligible);
    if ([...this.performed].some((t) => !held.has(t))) {
      this.performed.clear();
      this.pendingPerforms.length = 0;
      this.pendingPerforms.push("reset");
    }
    for (const t of eligible) {
      if (this.performed.has(t)) {
        continue;
      }
      this.performed.add(t);
      const p = t.cue.perform;
      this.pendingPerforms.push({
        action: p.action,
        payload: p.payload,
        target: p.target,
        time: t.start / this.scale / 1e3
      });
    }
    if (this.pendingPerforms.length && !this.performFlushBooked) {
      this.performFlushBooked = true;
      frame.postRender(() => {
        this.performFlushBooked = false;
        const queue = this.pendingPerforms;
        this.pendingPerforms = [];
        for (const item of queue) {
          if (item === "reset") {
            this.options.onPerformReset?.();
          } else {
            this.options.onPerform?.(item);
          }
        }
      });
    }
  }
  /**
   * Stand rewound tracks back on their origins — the part of a backward
   * seek that must be ORDERED. A sprite with sequential cues has one
   * origin per cue, each equal to the previous cue's landing; restored
   * in track order they clobber forward and the sprite ends up standing
   * on its LAST future cue's origin (the Playhead demo's hand parked on
   * 'place' after a scrub to zero; its receipt refusing to dismiss). So:
   * latest-first, which leaves the EARLIEST future cue's origin — the
   * value the timeline actually holds at `now` — standing; and a key
   * that any track AT or BEFORE `now` writes is not touched at all,
   * because that track's own sample or landing is the answer.
   */
  rewind(rewinds, now2) {
    rewinds.sort((a, b) => b.start - a.start);
    for (const t of rewinds) {
      const ve = t.cue.sprite.node.visualElement;
      if (!ve || !t.origin) {
        continue;
      }
      let wrote = false;
      for (const key in t.origin) {
        const owned = this.tracks.some((s) => s !== t && s.start <= now2 && s.cue.target !== void 0 && key in s.cue.target && s.cue.sprite.node.visualElement === ve);
        if (!owned) {
          ve.getValue(key, t.origin[key]).jump(t.origin[key]);
          wrote = true;
        }
      }
      if (wrote) {
        ve.render();
      }
    }
  }
  /** the eased progress of a plain clock-driven track */
  flightlessProgress(t, ms) {
    const span = t.end - t.start;
    const raw = span > 0 ? Math.min(1, Math.max(0, ms / span)) : 1;
    return easingDefinitionToFunction("easeInOut")(raw);
  }
  /* ---- c.Camera3D: the shot, for a scene Choreo does not draw ---- */
  /**
   * The orbit pose in force. Public for the same reason `camera` is: it is
   * hand-off state, and a replacement run must continue from where this
   * one left the shot rather than snapping back to the framing.
   */
  camera3d;
  initial3d;
  /* ---- c.Camera: the region's frame (§6.3) ---- */
  camera;
  /**
   * The aim point P in force, local px. With transform-origin pinned at
   * 0 0, the applied transform is translate(x + (1−z)·P) scale(z) — the
   * frame's centre cancels out of the algebra entirely, so neither a
   * board that reflows mid-cue nor a stage that changes height between
   * cues can move the picture: the formula reads no live DOM at all.
   * z = 1 is the identity for any P. Public because it is hand-off state:
   * the next run lerps from the point THIS run left aimed, exactly as it
   * inherits the camera.
   */
  cameraAim = null;
  /**
   * The absolute pose a camera cue lands on, resolved against the pose it
   * starts from. Absolute fields pass through; missing fields hold; a
   * relative cue (Pan / SlowZoom) offsets and multiplies the pose in
   * force — which is why resolution happens AT START (live) or during the
   * prefix fold (reconstruction), never at compile.
   */
  static resolveCameraTo(cue, from) {
    const {
      by,
      to: to2
    } = cue;
    return {
      x: by?.x !== void 0 ? from.x + by.x : to2.x ?? from.x,
      y: by?.y !== void 0 ? from.y + by.y : to2.y ?? from.y,
      zoom: by?.zoom !== void 0 ? from.zoom * by.zoom : to2.zoom ?? from.zoom
    };
  }
  cameraProgress(t, ms) {
    const span = t.end - t.start;
    const raw = span > 0 ? Math.min(1, Math.max(0, ms / span)) : 1;
    const transition = t.cue.transition;
    if (isSpring(transition)) {
      const generator = spring({
        keyframes: [0, 100],
        ...transition ?? {}
      });
      return generator.next(ms / this.scale).value / 100;
    }
    return easingDefinitionToFunction(transition?.ease ?? "easeInOut")(raw);
  }
  /**
   * The camera and aim this run inherited, frozen at construction — the
   * fold origin every reconstruction starts from. Public because a
   * replacement run that re-executes the SAME score must inherit this
   * origin, not the pose in force: the pose in force is what the score's
   * prefix already produced, and folding the prefix from it applies every
   * relative cue twice (the world-dock law).
   */
  initialCamera;
  initialAim;
  /**
   * Rebuild the camera fold from the score prefix before a seek's still
   * (notes/external-clock-camera-seek-handoff.md). Forward playback folds
   * each camera cue's landing into the run's cumulative camera as the
   * clock crosses it — but a random-access seek can jump clean over a
   * window, and a cue that never starts never folds: the clock reads `t`
   * while the picture holds an earlier shot. So every camera track's
   * bookkeeping (started, cameraFrom, aimFrom/aimTo, cameraP) is
   * re-derived here in timeline order from the run's initial camera;
   * evaluate() then recomputes exactly the numbers forward playback would
   * have produced, and play-after-scrub resumes from them. Pure
   * arithmetic over frozen numbers, like the rest of the camera: no DOM
   * is read, so backward and repeated seeks agree to the pixel.
   */
  reconstructCameraAt(limit) {
    const cams = this.tracks.filter((t) => t.cue.camera);
    if (!cams.length) {
      return;
    }
    const now2 = this.master;
    cams.sort((a, b) => a.start - b.start);
    const state = {
      ...this.initialCamera
    };
    let aim = this.initialAim ? {
      ...this.initialAim
    } : null;
    for (const t of cams) {
      if (!(now2 >= t.start && t.start < limit)) {
        t.started = false;
        t.passed = false;
        t.cameraP = 0;
        t.cameraTo = void 0;
        t.aimFrom = aim ?? void 0;
        t.aimTo = aim ?? void 0;
        t.cameraAnimation?.cancel();
        t.cameraAnimation = void 0;
        continue;
      }
      const cue = t.cue.camera;
      const aimTo = cue.origin ?? aim ?? cue.centre ?? {
        x: 0,
        y: 0
      };
      t.started = true;
      t.passed = false;
      t.cameraFrom = {
        ...state
      };
      t.cameraTo = _ChoreoRun.resolveCameraTo(cue, t.cameraFrom);
      t.aimFrom = aim ?? aimTo;
      t.aimTo = aimTo;
      aim = aimTo;
      if (now2 >= t.end) {
        state.x = t.cameraTo.x;
        state.y = t.cameraTo.y;
        state.zoom = t.cameraTo.zoom;
        t.cameraP = 1;
        t.cameraAnimation?.cancel();
        t.cameraAnimation = void 0;
      }
    }
    this.camera = state;
    this.cameraAim = aim;
    if (!cams.some((t) => t.started)) {
      this.applyCamera(cams[0]);
    }
  }
  /**
   * The damped counter-scale (§6.4): steady sprites scale with the host but
   * not 1:1 — pow(z, .30) zoomed out so they stay readable, pow(z, .70)
   * zoomed in so they don't feel stuck, clamped to what the eye tolerates.
   */
  static damped(zoom) {
    const target = Math.min(1.8, Math.max(0.85, Math.pow(zoom, zoom < 1 ? 0.3 : 0.7)));
    return target / zoom;
  }
  /**
   * The frame's APPLIED transform for a camera state at aim progress `p`.
   *
   * Transform-origin is pinned at 0 0, so the applied transform is
   * translate(x + (1−z)·P) scale(z) with P the lerped aim point — pure
   * arithmetic over frozen numbers. Nothing here reads the DOM, so a board
   * that reflows mid-cue cannot move the camera, and every boundary
   * (landing, re-aim, next run) agrees to the pixel. At z = 1 the aim term
   * vanishes: an unpanned camera is EXACTLY the identity.
   */
  appliedCamera(t, state, p) {
    const from = t.aimFrom ?? t.aimTo ?? {
      x: 0,
      y: 0
    };
    const to2 = t.aimTo ?? from;
    const aim = {
      x: from.x + (to2.x - from.x) * p,
      y: from.y + (to2.y - from.y) * p
    };
    return {
      x: state.x + (1 - state.zoom) * aim.x,
      y: state.y + (1 - state.zoom) * aim.y,
      zoom: state.zoom
    };
  }
  static cameraCss(a) {
    return a.zoom === 1 && a.x === 0 && a.y === 0 ? "" : `translate(${a.x}px, ${a.y}px) scale(${a.zoom})`;
  }
  /**
   * Fly the region's frame on the platform: two transform keyframes and the
   * eased clock pre-sampled into a linear() easing. The biggest layer in the
   * region composites off the main thread for the whole move.
   */
  startCameraAnimation(t, now2) {
    const host = this.options.cameraFrame;
    const from = t.cameraFrom;
    const cue = t.cue.camera;
    if (!host || !from || !cue) {
      return;
    }
    const final = t.cameraTo ?? _ChoreoRun.resolveCameraTo(cue, from);
    const span = Math.max(1, t.end - t.start);
    const anim = host.animate([{
      transform: _ChoreoRun.cameraCss(this.appliedCamera(t, from, 0)) || "none"
    }, {
      transform: _ChoreoRun.cameraCss(this.appliedCamera(t, final, 1)) || "none"
    }], {
      duration: span,
      easing: generateLinearEasing((p) => this.cameraProgress(t, p * span), span),
      fill: "both"
    });
    anim.playbackRate = this.rate;
    anim.currentTime = Math.max(0, now2 - t.start);
    t.cameraAnimation = anim;
  }
  /**
   * Retire the frame's platform animation and hand the picture back to
   * inline style, written from the shadow state — so a cancel mid-zoom
   * freezes exactly where the eye was, and a landing holds its final.
   */
  dropCameraAnimation(t) {
    if (!t.cameraAnimation) {
      return;
    }
    t.cameraAnimation.cancel();
    t.cameraAnimation = void 0;
    this.applyCamera(t);
  }
  applyCamera(t) {
    const frame2 = this.options.cameraFrame;
    if (!frame2) {
      return;
    }
    const {
      zoom
    } = this.camera;
    frame2.style.transformOrigin = "0px 0px";
    if (!t.cameraAnimation) {
      frame2.style.transform = _ChoreoRun.cameraCss(this.appliedCamera(t, this.camera, t.cameraP ?? 1));
    }
    for (const sprite of t.cue.camera?.steady ?? []) {
      const ve = sprite.node.visualElement;
      if (ve) {
        const counter = _ChoreoRun.damped(zoom);
        ve.getValue("scale", counter).set(counter);
      }
    }
  }
  /* ---- c.Tether: the wire that follows (§6.1) ---- */
  tetherDrawScheduled = false;
  scheduleTetherDraw() {
    if (this.tetherDrawScheduled) {
      return;
    }
    this.tetherDrawScheduled = true;
    frame.postRender(() => {
      this.tetherDrawScheduled = false;
      for (const t of this.tracks) {
        if (t.started && t.wire) {
          this.drawTether(t);
        }
      }
    });
  }
  /**
   * One frame of a derived value (§4.10): compose the context from the
   * pass's measurements, hand it to the author's function, write what
   * comes back.
   *
   * Nothing here touches the DOM — that is the design, not an
   * optimisation (docs/postmortem-follow.md). The resting boxes were
   * measured by the pass with every moved value released, and a source's
   * `now` is its resting box composed with the motion values driving it
   * this frame: JS-side numbers, not a measurement. So a follower is pure
   * BY CONSTRUCTION — there is no live box in reach, it cannot read back
   * its own output, and it cannot force a style recalculation in the
   * middle of a move. It is also correct under INTERRUPTION for free: a
   * replacement run's pass re-measures, so a run born mid-flight computes
   * from rests that are right immediately, with no "last frame" to
   * disagree with.
   *
   * `set`, not an animation: a derived value IS the frame, so there is
   * nothing to interpolate toward and nothing the compositor could be
   * given — this is the main-thread cost the step charges, and the reason
   * it is the same cost `c.Tether` already pays.
   */
  drive(t, now2) {
    const derive = t.cue.derive;
    const ve = t.cue.sprite.node.visualElement;
    if (!derive || !ve) {
      return;
    }
    const sources = derive.sources.map(({
      from,
      sprite,
      to: to2
    }) => {
      const sv = sprite.node.visualElement;
      const num2 = (key) => {
        const value = sv?.getValue(key)?.get();
        return typeof value === "number" ? value : void 0;
      };
      const sx = num2("scaleX") ?? num2("scale") ?? 1;
      const sy = num2("scaleY") ?? num2("scale") ?? 1;
      const width = to2.width * sx;
      const height = to2.height * sy;
      return {
        from,
        now: {
          height,
          width,
          x: to2.x + (num2("x") ?? 0) + (to2.width - width) / 2,
          y: to2.y + (num2("y") ?? 0) + (to2.height - height) / 2
        },
        to: to2
      };
    });
    const span = t.end - t.start;
    const values = derive.read({
      camera: {
        ...this.camera
      },
      elapsed: Math.max(0, now2 - t.start) / this.scale / 1e3,
      p: span > 0 ? Math.max(0, Math.min(1, (now2 - t.start) / span)) : 1,
      rest: {
        ...derive.restBox
      },
      sources,
      t: now2 / 1e3
    });
    for (const [key, value] of Object.entries(values)) {
      ve.getValue(key, value).set(value);
    }
    ve.render();
  }
  /** the window closed (or was scrubbed out of): put the declared rest back */
  restDerived(t) {
    const rest = t.cue.derive?.rest;
    const ve = t.cue.sprite.node.visualElement;
    if (!rest || !ve) {
      return;
    }
    for (const [key, value] of Object.entries(rest)) {
      ve.getValue(key, value).jump(value);
    }
    ve.render();
  }
  drawTether(t) {
    const layer = this.options.tetherLayer;
    const tether = t.cue.tether;
    if (!layer || !tether || !t.wire) {
      return;
    }
    const inverse = layer.getScreenCTM()?.inverse();
    const box = layer.getBoundingClientRect();
    const toLocal2 = (clientX, clientY) => {
      if (!inverse) {
        return {
          x: clientX - box.left,
          y: clientY - box.top
        };
      }
      const p = new DOMPoint(clientX, clientY).matrixTransform(inverse);
      return {
        x: p.x,
        y: p.y
      };
    };
    const rectOf = (sprite) => {
      const el = sprite?.element;
      if (!el?.isConnected) {
        return null;
      }
      const r = el.getBoundingClientRect();
      const tl = toLocal2(r.left, r.top);
      const br = toLocal2(r.right, r.bottom);
      return {
        height: br.y - tl.y,
        width: br.x - tl.x,
        x: tl.x,
        y: tl.y
      };
    };
    const a = rectOf(tether.from);
    const b = rectOf(tether.to);
    if (a && b) {
      t.wire.setAttribute("d", tether.path(a, b));
    }
  }
  /* ---- c.Raise: the elevated layer (§6.3) ---- */
  /**
   * The scale between the layer's own pixels and the screen's, per axis.
   *
   * A promotion reads client rects and writes LOCAL pixels, and every
   * transform above the region — a camera zoom, a page crossing carrying the
   * whole scene, any ancestor with a scale on it — sits between the two. Read
   * off the layer itself: its rect is what the screen shows, its offset size
   * is what its own coordinate system calls that. Dividing by the camera zoom
   * alone would catch the region's own transform and miss everything outside
   * it, which is the double-scale the tether draw already dodges by mapping
   * through the screen CTM.
   */
  static layerScale(el, box) {
    return {
      x: el.offsetWidth ? box.width / el.offsetWidth : 1,
      y: el.offsetHeight ? box.height / el.offsetHeight : 1
    };
  }
  promote(t) {
    const layer = this.options.raisedLayer;
    const el = t.cue.sprite.element;
    if (!layer || !el.isConnected || t.perch) {
      return;
    }
    const box = el.getBoundingClientRect();
    const layerBox = layer.getBoundingClientRect();
    const s = _ChoreoRun.layerScale(layer, layerBox);
    const width = box.width / s.x;
    const height = box.height / s.y;
    const placeholder = document.createElement(el.tagName);
    placeholder.setAttribute("aria-hidden", "true");
    placeholder.style.cssText = `visibility:hidden;width:${width}px;height:${height}px;margin:0;flex:none`;
    const prior = el.style.cssText;
    el.parentNode?.insertBefore(placeholder, el);
    layer.appendChild(el);
    el.style.position = "absolute";
    el.style.left = `${(box.left - layerBox.left) / s.x}px`;
    el.style.top = `${(box.top - layerBox.top) / s.y}px`;
    el.style.width = `${width}px`;
    el.style.height = `${height}px`;
    el.style.margin = "0";
    if (t.cue.raise?.shadow) {
      el.style.filter = "drop-shadow(0 18px 24px rgba(0,0,0,0.35))";
    }
    t.perch = {
      placeholder,
      prior
    };
  }
  restore(t) {
    const el = t.cue.sprite.element;
    const perch = t.perch;
    if (!perch) {
      return;
    }
    t.perch = void 0;
    perch.placeholder.parentNode?.replaceChild(el, perch.placeholder);
    el.style.cssText = perch.prior;
    t.cue.sprite.node.visualElement?.scheduleRender();
  }
  /* ---- c.Scroll: the container as a step (§6.1) ---- */
  startScroll(t) {
    const el = t.cue.sprite.element;
    let container = el.parentElement;
    while (container) {
      const cs = getComputedStyle(container);
      if (/(auto|scroll)/.test(cs.overflowY + cs.overflowX)) {
        break;
      }
      container = container.parentElement;
    }
    if (!container) {
      return;
    }
    const box = el.getBoundingClientRect();
    const cBox = container.getBoundingClientRect();
    const s = _ChoreoRun.layerScale(container, cBox);
    const align = t.cue.scroll.align;
    const offsetY = (box.top - cBox.top) / s.y + container.scrollTop;
    const offsetX = (box.left - cBox.left) / s.x + container.scrollLeft;
    const factor = align === "center" ? 0.5 : align === "end" ? 1 : 0;
    const to2 = {
      left: Math.max(0, offsetX - (container.clientWidth - box.width / s.x) * factor),
      top: Math.max(0, offsetY - (container.clientHeight - box.height / s.y) * factor)
    };
    const onWheel = () => this.stopScroll(t, false);
    container.addEventListener("wheel", onWheel, {
      passive: true
    });
    container.addEventListener("touchmove", onWheel, {
      passive: true
    });
    t.scrolling = {
      cancelListener: () => {
        container.removeEventListener("wheel", onWheel);
        container.removeEventListener("touchmove", onWheel);
      },
      container,
      from: {
        left: container.scrollLeft,
        top: container.scrollTop
      },
      to: to2
    };
  }
  stopScroll(t, rewind) {
    const s = t.scrolling;
    if (!s) {
      return;
    }
    t.scrolling = void 0;
    s.cancelListener();
    if (rewind) {
      s.container.scrollTop = s.from.top;
      s.container.scrollLeft = s.from.left;
    }
  }
  /** stop a track's animations at the value level — an async animation
   *  cancelled before it resolves stays 'idle' forever if only the controls
   *  are stopped, and its value then reads as animating for good */
  stopTrack(t) {
    t.controls?.forEach((c) => c.stop());
    t.controls = void 0;
    t.platform?.forEach((a) => a.cancel());
    t.platform = void 0;
    const ve = t.cue.sprite.node.visualElement;
    if (ve && t.cue.target) {
      for (const key in t.cue.target) {
        ve.getValue(key)?.stop();
      }
    }
  }
  /** land a cue's end values without ever having played it */
  jumpFinals(t) {
    const {
      cue
    } = t;
    const ve = cue.sprite.node.visualElement;
    if (!ve || !cue.target && !cue.flight) {
      return;
    }
    if (cue.flight) {
      this.applyFlight(t, 1);
      ve.render();
      if (!cue.target) {
        t.passed = true;
        return;
      }
    }
    if (!t.origin) {
      const origin = {};
      for (const key in cue.target) {
        const value = cue.target[key];
        if (Array.isArray(value)) {
          origin[key] = value[0];
        } else {
          const held = ve.getValue(key)?.get();
          origin[key] = held !== void 0 ? held : getComputedStyle(cue.sprite.element).getPropertyValue(dash(key)) || 0;
        }
      }
      t.origin = origin;
    }
    t.passed = true;
    for (const key in cue.target) {
      const end = finalOf(cue, key);
      ve.getValue(key, end).jump(end);
    }
    ve.render();
  }
  startTrack(t) {
    const {
      cue
    } = t;
    const ve = cue.sprite.node.visualElement;
    if (!ve) {
      return;
    }
    t.started = true;
    t.passed = false;
    if (cue.target && !t.origin) {
      const origin = {};
      for (const key in cue.target) {
        const value = cue.target[key];
        if (Array.isArray(value)) {
          origin[key] = value[0];
        } else {
          const held = ve.getValue(key)?.get();
          const latest = ve.latestValues[key];
          origin[key] = held !== void 0 ? held : latest !== void 0 ? latest : getComputedStyle(cue.sprite.element).getPropertyValue(dash(key)) || 0;
        }
      }
      t.origin = origin;
    }
    if (cue.delivery) {
      for (const key in cue.target) {
        const raw = cue.target[key];
        if (Array.isArray(raw)) {
          const end = raw[raw.length - 1];
          ve.getValue(key, end).jump(end);
        }
      }
      ve.render();
      t.delivery = deliver(cue, this.scale);
      if (!this.playing) {
        t.delivery.pause();
      }
      return;
    }
    if (cue.loop) {
      const el = cue.sprite.element;
      const cycle = t.end - t.start;
      const {
        ease: ease3,
        times
      } = cue.transition ?? {};
      const frames2 = keyframesOf(cue.target ?? {});
      if (times) {
        frames2.offset = times;
      }
      const segmented = Array.isArray(ease3) && typeof ease3[0] !== "number";
      if (segmented) {
        const each = ease3.map((e) => cssEasing(e, cycle));
        frames2.easing = [...each, "linear"];
      }
      t.loopAnimation = el.animate(frames2, {
        duration: Math.max(1, cycle),
        easing: segmented ? "linear" : cssEasing(ease3, cycle),
        iterations: Infinity
      });
      t.loopAnimation.playbackRate = this.rate;
      if (!this.playing) {
        t.loopAnimation.pause();
      }
      return;
    }
    if (cue.flight) {
      this.startFlight(t);
      return;
    }
    if (!cue.target) {
      return;
    }
    if (!this.playing) {
      this.sampleStill(t, this.master);
      return;
    }
    const transition = carryVelocity(scaleTransition({
      ...cue.transition
    }, this.scale), cue, this.options.inherit);
    t.controls = animateTarget(ve, {
      ...cue.target,
      transition
    });
    for (const c of t.controls) {
      c.speed = this.rate;
    }
  }
  /** put the sprite at progress `p` of its sampled flight path (§4.4) */
  applyFlight(t, p) {
    const {
      cue
    } = t;
    const ve = cue.sprite.node.visualElement;
    const flight = cue.flight;
    if (!ve || !flight) {
      return;
    }
    const pts = flight.points;
    const at2 = Math.min(pts.length - 1 - 1e-9, Math.max(0, p) * (pts.length - 1));
    const index = Math.floor(at2);
    const local = at2 - index;
    const a = pts[index];
    const b = pts[Math.min(index + 1, pts.length - 1)];
    const x = a.x + (b.x - a.x) * local - flight.rest.x;
    const y = a.y + (b.y - a.y) * local - flight.rest.y;
    ve.getValue("x", x).set(x);
    ve.getValue("y", y).set(y);
    if (flight.rotate !== void 0) {
      const angle = Math.atan2(b.y - a.y, b.x - a.x) * 180 / Math.PI + (typeof flight.rotate === "number" ? flight.rotate : 0);
      ve.getValue("rotate", angle).set(angle);
    }
  }
  /** the eased progress a flight sits at, `ms` into its window */
  flightProgress(t, ms) {
    const span = t.end - t.start;
    const raw = span > 0 ? Math.min(1, Math.max(0, ms / span)) : 1;
    const transition = t.cue.transition;
    if (isSpring(transition)) {
      const pts = t.cue.flight.points;
      const end = pts[pts.length - 1];
      const distance2 = Math.hypot(end.x, end.y) || 1;
      const generator = spring({
        keyframes: [0, distance2],
        ...transition ?? {}
      });
      return generator.next(ms / this.scale).value / distance2;
    }
    return easingDefinitionToFunction(transition?.ease ?? "easeInOut")(raw);
  }
  /**
   * The sampled path as platform keyframes: each point becomes a transform,
   * uniformly spaced (the points were sampled uniformly in progress), and
   * the eased clock rides the animation's easing instead of per-frame JS.
   */
  flightKeyframes(t) {
    const flight = t.cue.flight;
    const pts = flight.points;
    const frames2 = [];
    for (let i = 0; i < pts.length; i++) {
      const p = pts[i];
      let transform = `translate(${p.x - flight.rest.x}px, ${p.y - flight.rest.y}px)`;
      if (flight.rotate !== void 0) {
        const a = pts[Math.max(0, i - 1)];
        const b = pts[Math.min(pts.length - 1, i + 1)];
        const angle = Math.atan2(b.y - a.y, b.x - a.x) * 180 / Math.PI + (typeof flight.rotate === "number" ? flight.rotate : 0);
        transform += ` rotate(${angle}deg)`;
      }
      frames2.push({
        transform
      });
    }
    return frames2;
  }
  startFlight(t) {
    const {
      cue
    } = t;
    const ve = cue.sprite.node.visualElement;
    if (!ve) {
      return;
    }
    if (!this.playing) {
      this.sampleStill(t, this.master);
      return;
    }
    const span = Math.max(1, t.end - t.start);
    const controls = [];
    const anim = cue.sprite.element.animate(this.flightKeyframes(t), {
      duration: span,
      easing: generateLinearEasing((p) => this.flightProgress(t, p * span), span),
      fill: "both"
    });
    anim.playbackRate = this.rate;
    anim.currentTime = Math.min(span, Math.max(0, this.master - t.start));
    (t.platform ??= []).push(anim);
    controls.push(platformControls(anim));
    if (cue.target && Object.keys(cue.target).length) {
      const transition = scaleTransition({
        ...cue.transition,
        onUpdate: noop2
      }, this.scale);
      controls.push(...animateTarget(ve, {
        ...cue.target,
        transition
      }));
    }
    for (const c of controls) {
      c.speed = this.rate;
    }
    t.controls = controls;
  }
  /**
   * Compute one still frame of a cue and jump the values onto the element.
   *
   * A tween is sampled with motion-dom's OWN keyframes generator — the one
   * its playback runs — so a seek and a play are the same arithmetic:
   * `@times`, one ease per segment, and every value type motion can mix
   * (colours, clip-paths and filters token by token, units kept). The old
   * path parsed every keyframe with parseFloat, which snapped anything
   * non-numeric to its nearest keyframe and ran one ease across the whole
   * array — a render and a playback that disagreed.
   *
   * A finite `@repeat` folds the window into (play, time in play) the way
   * motion's JSAnimation does: `loop` restarts, `mirror` plays the
   * keyframes reversed on odd plays, `reverse` runs odd plays backwards in
   * time, and an exact play boundary is the END of the play before it.
   */
  sampleStill(t, now2) {
    const {
      cue
    } = t;
    const ve = cue.sprite.node.visualElement;
    if (!ve || !cue.target && !cue.flight) {
      return;
    }
    if (cue.flight) {
      this.applyFlight(t, this.flightProgress(t, now2 - t.start));
      ve.render();
      if (!cue.target) {
        return;
      }
    }
    const span = t.end - t.start;
    const transition = cue.transition;
    const sprung = isSpring(transition);
    const plays = playsOf(transition);
    const play = span / plays;
    const local = Math.min(span, Math.max(0, now2 - t.start));
    let index = play > 0 ? Math.floor(local / play) : 0;
    let inPlay = local - index * play;
    if (index > 0 && (index >= plays || inPlay <= 0)) {
      index = Math.min(index, plays) - 1;
      inPlay = play;
    }
    const odd = index % 2 === 1;
    if (odd && transition?.repeatType === "reverse") {
      inPlay = play - inPlay;
    }
    const mirrored = odd && transition?.repeatType === "mirror";
    for (const key in cue.target) {
      const raw = cue.target[key];
      let frames2 = Array.isArray(raw) ? raw : [t.origin?.[key] ?? 0, raw];
      if (mirrored) {
        frames2 = [...frames2].reverse();
      }
      let value;
      if (sprung) {
        const numeric = frames2.map((f) => parseFloat(String(f)));
        if (numeric.some((n) => Number.isNaN(n))) {
          value = nearest(frames2, span > 0 ? local / span : 1);
        } else {
          const generator = spring({
            keyframes: [numeric[0], numeric[numeric.length - 1]],
            ...transition ?? {}
          });
          value = generator.next(now2 - t.start).value;
        }
      } else {
        value = mixed(frames2, inPlay, play, transition);
      }
      ve.getValue(key, value).jump(value);
    }
    ve.render();
  }
  completeTrack(t) {
    const {
      cue
    } = t;
    if (t.passed) {
      return;
    }
    t.passed = true;
    t.started = false;
    flushKeyframeResolvers();
    this.stopTrack(t);
    if (t.delivery) {
      t.delivery.complete();
      t.delivery = void 0;
    }
    const ve = cue.sprite.node.visualElement;
    if (ve && cue.flight) {
      this.applyFlight(t, 1);
      ve.render();
    }
    if (ve && cue.target) {
      for (const key in cue.target) {
        const end = finalOf(cue, key);
        ve.getValue(key, end).jump(end);
      }
      ve.render();
    }
  }
  /* ---- starting values, velocities, and giving the layout back ---- */
  pinStarts() {
    const pinned = /* @__PURE__ */ new Set();
    const rendered = /* @__PURE__ */ new Set();
    for (const t of [...this.tracks].sort((a, b) => a.start - b.start)) {
      const cue = t.cue;
      const ve = cue.sprite.node.visualElement;
      if (!ve || cue.loop) {
        continue;
      }
      if (cue.flight) {
        this.movedValues.push({
          key: "x",
          ve
        }, {
          key: "y",
          ve
        });
        this.owned.push({
          el: cue.sprite.element,
          key: "x",
          ve
        }, {
          el: cue.sprite.element,
          key: "y",
          ve
        });
        if (cue.flight.rotate !== void 0) {
          this.movedValues.push({
            key: "rotate",
            ve
          });
        }
        this.applyFlight({
          ...t
        }, 0);
        rendered.add(ve);
      }
      if (!cue.target) {
        continue;
      }
      for (const key in cue.target) {
        const value = cue.target[key];
        if (!Array.isArray(value) || value[0] === void 0) {
          continue;
        }
        const seen = `${cue.sprite.node.layoutKey}:${key}`;
        if (pinned.has(seen)) {
          continue;
        }
        pinned.add(seen);
        this.owned.push({
          el: cue.sprite.element,
          key,
          ve
        });
        if (cue.kind === "move") {
          if (key in SIZES) {
            if (!ve.hasValue(key)) {
              this.borrowedValues.push({
                el: cue.sprite.element,
                key,
                prior: cue.sprite.element.style.getPropertyValue(dash(key)),
                ve
              });
            }
          } else {
            this.movedValues.push({
              key,
              rest: key.startsWith("scale") ? 1 : key === "clipPath" ? "none" : 0,
              ve
            });
          }
        } else if (cue.borrow && !ve.hasValue(key)) {
          this.borrowedValues.push({
            el: cue.sprite.element,
            key,
            prior: cue.sprite.element.style.getPropertyValue(dash(key)),
            ve
          });
        }
        ve.getValue(key, value[0]).jump(value[0]);
        rendered.add(ve);
      }
    }
    rendered.forEach((ve) => ve.render());
  }
  sampleVelocities() {
    for (const {
      ve,
      el,
      key
    } of this.owned) {
      let byKey = this.velocities.get(el);
      if (byKey?.has(key)) {
        continue;
      }
      const velocity = ve.getValue(key)?.getVelocity();
      if (!velocity) {
        continue;
      }
      if (!byKey) {
        this.velocities.set(el, byKey = /* @__PURE__ */ new Map());
      }
      byKey.set(key, velocity);
    }
  }
  releaseForMeasure() {
    this.sampleVelocities();
    for (const t of this.tracks) {
      t.platform?.forEach((a) => a.cancel());
      t.platform = void 0;
      this.dropCameraAnimation(t);
    }
    const touched = /* @__PURE__ */ new Set();
    this.retired = {
      borrowed: [],
      moved: []
    };
    for (const {
      ve,
      el,
      key,
      prior
    } of this.borrowedValues.splice(0)) {
      this.retired.borrowed.push({
        el,
        key,
        prior,
        value: ve.getValue(key)?.get(),
        ve
      });
      ve.removeValue(key);
      if (prior) {
        el.style.setProperty(dash(key), prior);
      } else {
        el.style.removeProperty(dash(key));
      }
      touched.add(ve);
    }
    for (const {
      ve,
      key,
      rest
    } of this.movedValues.splice(0)) {
      this.retired.moved.push({
        key,
        rest,
        value: ve.getValue(key)?.get(),
        ve
      });
      ve.getValue(key)?.jump(rest ?? 0);
      touched.add(ve);
    }
    touched.forEach((ve) => ve.render());
  }
  /**
   * A pass measured this run's world at rest and then decided to KEEP the
   * run — but the measurement itself was destructive: releaseForMeasure
   * cancels platform animations, returns borrowed values, and jumps every
   * moved value to rest, and a MotionValue.jump() STOPS the animation
   * driving it. Left like that, a kept run keeps its clock and its landing
   * but loses its picture: the flight freezes at rest until the finals
   * land — which on a busy page (the gallery: neighbours re-pass the
   * region every render) is every crossing, every time. So the keep path
   * calls this: moved and borrowed values are stood back where they were,
   * their bookkeeping is re-registered, every in-flight track's animation
   * is retired so evaluate re-enters it — the machinery a scrub-then-play
   * already uses — and the re-entered animations are seeked back onto the
   * run's own clock, so a keep is invisible rather than a restart.
   */
  reassert() {
    const {
      borrowed,
      moved
    } = this.retired;
    this.retired = {
      borrowed: [],
      moved: []
    };
    for (const {
      el,
      key,
      prior,
      value,
      ve
    } of borrowed) {
      if (value !== void 0) {
        ve.getValue(key, value).jump(value);
      }
      this.borrowedValues.push({
        el,
        key,
        prior,
        ve
      });
    }
    for (const {
      key,
      rest,
      value,
      ve
    } of moved) {
      if (value !== void 0) {
        ve.getValue(key)?.jump(value);
      }
      this.movedValues.push({
        key,
        rest,
        ve
      });
    }
    if (!this.playing) {
      return;
    }
    const now2 = this.master;
    const restarted = [];
    for (const t of this.tracks) {
      if (t.started && !t.passed && now2 >= t.start && (now2 < t.end || t.cue.loop) && (t.cue.target || t.cue.flight)) {
        flushKeyframeResolvers();
        this.stopTrack(t);
        restarted.push(t);
      }
    }
    this.evaluate();
    for (const t of restarted) {
      if (!t.cue.flight) {
        const at2 = Math.max(0, now2 - t.start) / 1e3;
        t.controls?.forEach((c) => {
          c.time = at2;
        });
      }
    }
  }
  cancel(keep) {
    if (this.cancelled) {
      return;
    }
    this.cancelled = true;
    activeRuns.delete(this);
    this.stopTicking();
    clearTimeout(this.autoTimer);
    this.pendingPerforms.length = 0;
    this.options.onCamera?.({
      ...this.camera
    });
    flushKeyframeResolvers();
    this.sampleVelocities();
    for (const t of this.tracks) {
      this.stopTrack(t);
      t.delivery?.cancel();
      t.loopAnimation?.cancel();
      this.dropCameraAnimation(t);
      this.restore(t);
      this.stopScroll(t, false);
      t.wire?.remove();
      t.wire = void 0;
      const ve = t.cue.sprite.node.visualElement;
      if (t.held && ve) {
        releaseHold(ve, t.cue.sprite.element, t.held);
        t.held = void 0;
      }
    }
    this.releaseForMeasure();
    for (const sprite of [...this.pending]) {
      if (keep?.has(sprite.node)) {
        this.pending.delete(sprite);
      } else {
        this.pending.delete(sprite);
        this.options.onSpriteDone(sprite);
      }
    }
    this.resolveFinished();
  }
};
var activeRuns = /* @__PURE__ */ new Set();
function execute(compiled, options) {
  return new ChoreoRun(compiled, options);
}

// dist/choreo/steps.js
import Component from "@glimmer/component";
import { modifier as modifier2 } from "ember-modifier";

// dist/choreo/anchors.js
function at(name, progress2 = 0) {
  return {
    anchor: name,
    edge: "start",
    progress: progress2
  };
}
function after(name, delay2 = 0) {
  return {
    anchor: name,
    delay: delay2,
    edge: "end"
  };
}

// dist/choreo/steps.js
import { precompileTemplate } from "@ember/template-compilation";
import { setComponentTemplate } from "@ember/component";
var providers = /* @__PURE__ */ new WeakMap();
var crossings = 0;
function collect(el) {
  const out = [];
  for (const child of Array.from(el.children)) {
    if (child.hasAttribute("data-choreo")) {
      continue;
    }
    const provider = providers.get(child);
    if (provider) {
      out.push(provider.node());
    } else {
      out.push(...collect(child));
    }
  }
  return out;
}
var RESERVED = /* @__PURE__ */ new Set(["align", "at", "by", "delay", "duration", "ease", "fill", "from", "name", "of", "order", "origin", "path", "read", "repeat", "repeatType", "rest", "rings", "shadow", "size", "space", "spring", "stagger", "swap", "times", "to", "vars"]);
var RENAMED = {
  crossfade: "@swap",
  ms: "@duration (in seconds)",
  overlap: "@stagger (in seconds)"
};
function propsOf(args) {
  const props = {};
  for (const key of Object.keys(args)) {
    if (args[key] === void 0) {
      continue;
    }
    if (RENAMED[key]) {
      throw new Error(`choreo: @${key} was renamed \u2014 use ${RENAMED[key]}`);
    }
    if (!RESERVED.has(key)) {
      props[key] = args[key];
    }
  }
  const vars = args["vars"];
  for (const name of Object.keys(vars ?? {})) {
    const bare = name.replace(/^--/, "");
    if (props[bare] !== void 0) {
      throw new Error(`choreo: @vars key '${bare}' collides with @${bare} \u2014 a custom property is always --named; rename one of them`);
    }
    if (vars[name] !== void 0) {
      props[`--${bare}`] = vars[name];
    }
  }
  return props;
}
function toMs(seconds) {
  return seconds === void 0 ? void 0 : seconds * 1e3;
}
var msOf = toMs;
var StepComponent = class extends Component {
  mark = modifier2((el) => {
    providers.set(el, this);
    return () => providers.delete(el);
  });
  static {
    setComponentTemplate(precompileTemplate("\n    <span hidden data-choreo-step {{this.mark}}></span>\n  ", {
      strictMode: true
    }), this);
  }
};
var Tween = class extends StepComponent {
  node() {
    const {
      of,
      by,
      duration,
      ease: ease3,
      delay: delay2,
      order,
      origin,
      repeat,
      repeatType,
      rings,
      times
    } = this.args;
    return {
      at: this.args.at,
      by,
      delay: msOf(delay2),
      ease: ease3,
      kind: "tween",
      name: this.args.name,
      ms: duration * 1e3,
      of,
      order,
      origin,
      props: propsOf(this.args),
      repeat,
      repeatType,
      rings,
      stagger: msOf(this.args.stagger),
      times
    };
  }
};
var Spring = class extends StepComponent {
  node() {
    const {
      of,
      by,
      spring: spring3,
      delay: delay2,
      order,
      origin,
      rings
    } = this.args;
    return {
      at: this.args.at,
      by,
      delay: msOf(delay2),
      kind: "spring",
      name: this.args.name,
      of,
      order,
      origin,
      props: propsOf(this.args),
      rings,
      spring: spring3,
      stagger: msOf(this.args.stagger)
    };
  }
};
var Move = class extends StepComponent {
  node() {
    const {
      of,
      duration,
      ease: ease3,
      delay: delay2,
      path,
      rotate: rotate2,
      space,
      spring: spring3,
      size,
      swap,
      from,
      to: to2,
      stagger: stagger2
    } = this.args;
    propsOf(this.args);
    return {
      at: this.args.at,
      delay: msOf(delay2),
      ease: ease3,
      from,
      kind: "move",
      name: this.args.name,
      ms: msOf(duration),
      of,
      path,
      rotate: rotate2,
      size,
      space,
      spring: spring3,
      stagger: msOf(stagger2),
      swap,
      to: to2
    };
  }
};
var Hold = class extends StepComponent {
  node() {
    const {
      of,
      duration,
      delay: delay2,
      fill,
      stagger: stagger2
    } = this.args;
    return {
      at: this.args.at,
      delay: msOf(delay2),
      fill,
      kind: "hold",
      name: this.args.name,
      ms: msOf(duration),
      of,
      props: propsOf(this.args),
      stagger: msOf(stagger2)
    };
  }
};
var Wait = class extends StepComponent {
  node() {
    const {
      of,
      duration,
      delay: delay2,
      stagger: stagger2
    } = this.args;
    return {
      at: this.args.at,
      delay: msOf(delay2),
      kind: "wait",
      name: this.args.name,
      ms: duration * 1e3,
      of,
      stagger: msOf(stagger2)
    };
  }
};
var Perform = class extends StepComponent {
  node() {
    const {
      action,
      delay: delay2,
      payload,
      target
    } = this.args;
    return {
      action,
      at: this.args.at,
      delay: msOf(delay2),
      kind: "perform",
      name: this.args.name,
      payload,
      target
    };
  }
};
var Attach = class extends StepComponent {
  node() {
    const {
      delay: delay2,
      duration,
      end,
      exact,
      rate,
      region
    } = this.args;
    return {
      at: this.args.at,
      delay: msOf(delay2),
      end,
      exact,
      in: this.args.in,
      kind: "attach",
      ms: duration * 1e3,
      name: this.args.name,
      rate,
      region
    };
  }
};
var Scroll = class extends StepComponent {
  node() {
    const {
      of,
      align,
      duration,
      delay: delay2,
      stagger: stagger2
    } = this.args;
    return {
      align,
      at: this.args.at,
      delay: msOf(delay2),
      kind: "scroll",
      ms: msOf(duration),
      name: this.args.name,
      of,
      stagger: msOf(stagger2)
    };
  }
};
var Raise = class extends StepComponent {
  node() {
    const {
      of,
      duration,
      delay: delay2,
      shadow,
      stagger: stagger2
    } = this.args;
    return {
      at: this.args.at,
      delay: msOf(delay2),
      kind: "raise",
      ms: msOf(duration),
      name: this.args.name,
      of,
      shadow,
      stagger: msOf(stagger2)
    };
  }
};
var Camera = class extends StepComponent {
  node() {
    const {
      duration,
      ease: ease3,
      delay: delay2,
      fit,
      margin,
      origin,
      spring: spring3,
      steady
    } = this.args;
    const {
      x,
      y,
      zoom
    } = this.args;
    return {
      at: this.args.at,
      delay: msOf(delay2),
      ease: ease3,
      fit,
      kind: "camera",
      margin,
      ms: msOf(duration),
      name: this.args.name,
      of: this.args.of ?? {},
      origin,
      spring: spring3,
      steady,
      x,
      y,
      zoom
    };
  }
};
var Camera3D = class extends StepComponent {
  node() {
    const {
      by,
      delay: delay2,
      dolly,
      duration,
      ease: ease3,
      look,
      pitch,
      spring: spring3,
      tension,
      through,
      x,
      y,
      yaw
    } = this.args;
    return {
      at: this.args.at,
      by,
      delay: msOf(delay2),
      dolly,
      ease: ease3,
      kind: "camera3d",
      look,
      ms: msOf(duration),
      name: this.args.name,
      of: this.args.of ?? {},
      pitch,
      spring: spring3,
      tension,
      through,
      x,
      y,
      yaw
    };
  }
};
var Frame = class extends StepComponent {
  node() {
    const {
      duration,
      ease: ease3,
      delay: delay2,
      of,
      padding,
      spring: spring3,
      steady
    } = this.args;
    return {
      at: this.args.at,
      delay: msOf(delay2),
      ease: ease3,
      fit: of,
      kind: "camera",
      margin: padding,
      ms: msOf(duration),
      name: this.args.name,
      of: {},
      spring: spring3,
      steady
    };
  }
};
var Aim = class extends StepComponent {
  node() {
    const {
      duration,
      ease: ease3,
      delay: delay2,
      of,
      spring: spring3,
      steady
    } = this.args;
    return {
      aim: of,
      at: this.args.at,
      delay: msOf(delay2),
      ease: ease3,
      kind: "camera",
      ms: msOf(duration),
      name: this.args.name,
      of: {},
      spring: spring3,
      steady
    };
  }
};
var Pan = class extends StepComponent {
  node() {
    const {
      duration,
      ease: ease3,
      delay: delay2,
      spring: spring3,
      steady,
      x,
      y
    } = this.args;
    return {
      at: this.args.at,
      delay: msOf(delay2),
      ease: ease3,
      kind: "camera",
      ms: msOf(duration),
      name: this.args.name,
      of: {},
      panBy: {
        x,
        y
      },
      spring: spring3,
      steady
    };
  }
};
var SlowZoom = class extends StepComponent {
  node() {
    const {
      by,
      duration,
      ease: ease3,
      delay: delay2,
      spring: spring3,
      steady
    } = this.args;
    return {
      at: this.args.at,
      delay: msOf(delay2),
      ease: ease3,
      kind: "camera",
      ms: msOf(duration),
      name: this.args.name,
      of: {},
      spring: spring3,
      steady,
      zoomBy: by
    };
  }
};
var Tether = class extends StepComponent {
  node() {
    const {
      duration,
      delay: delay2,
      from,
      path,
      to: to2
    } = this.args;
    return {
      at: this.args.at,
      delay: msOf(delay2),
      from,
      kind: "tether",
      ms: msOf(duration),
      name: this.args.name,
      of: this.args.of,
      path,
      to: to2
    };
  }
};
var Crossing = class extends StepComponent {
  /**
  * The flight is addressable from outside — `{{at 'page:flight' 0.5}}`
  * for a step that wants to ride the move itself. Derived from this
  * crossing's own `@name` rather than fixed, so two crossings in one
  * timeline do not collide over it; unnamed, it takes a per-instance
  * number, which is stable for the life of the component and so does not
  * disturb the tree fingerprint between passes.
  */
  flightName = `${this.args.name ?? `crossing-${++crossings}`}:flight`;
  node() {
    const {
      arrive = 0.22,
      duration,
      ease: ease3,
      leave: leave2 = 0.18,
      overlap = 0.7,
      size = "crop",
      spring: spring3,
      swap
    } = this.args;
    const FLIGHT = this.flightName;
    return {
      at: this.args.at,
      delay: toMs(this.args.delay),
      name: this.args.name,
      children: [{
        generic: true,
        kind: "tween",
        ms: toMs(leave2),
        of: {
          onstage: true,
          type: "departed"
        },
        props: {
          opacity: 0
        }
      }, {
        ease: ease3,
        generic: true,
        kind: "move",
        ms: toMs(duration),
        name: FLIGHT,
        of: {
          type: "received"
        },
        // iOS's rule: uniform scale matched by cover, the aspect mismatch
        // cropped by the interpolating window — never a stretch, and
        // never layout (a receiver animating real width/height reflows
        // its whole row for the flight). Overridable; the default stays
        // crop so a crossing in a grid cannot stretch the row.
        size,
        spring: spring3,
        swap
      }, {
        generic: true,
        kind: "hold",
        of: {
          type: "received"
        },
        props: {
          zIndex: 2
        }
      }, {
        at: at(FLIGHT, overlap),
        generic: true,
        kind: "tween",
        ms: toMs(arrive),
        of: {
          onstage: true,
          type: "inserted"
        },
        props: {
          opacity: [0, 1]
        }
      }],
      kind: "parallel"
    };
  }
};
var Follow = class extends StepComponent {
  node() {
    const {
      duration,
      of,
      read,
      rest,
      to: to2
    } = this.args;
    return {
      at: this.args.at,
      delay: msOf(this.args.delay),
      kind: "follow",
      ms: msOf(duration),
      name: this.args.name,
      of,
      read,
      rest,
      stagger: msOf(this.args.stagger),
      to: to2
    };
  }
};
var Gate = class extends Component {
  node() {
    return {
      kind: "gate",
      ms: msOf(this.args.delay)
    };
  }
  mark = modifier2((el) => {
    providers.set(el, this);
    return () => providers.delete(el);
  });
  static {
    setComponentTemplate(precompileTemplate("\n    <span hidden data-choreo-step {{this.mark}}></span>\n  ", {
      strictMode: true
    }), this);
  }
};
var BlockComponent = class extends Component {
  kind;
  el;
  node() {
    return {
      at: this.args.at,
      children: this.el ? collect(this.el) : [],
      delay: msOf(this.args.delay),
      kind: this.kind,
      name: this.args.name
    };
  }
  mark = modifier2((el) => {
    this.el = el;
    providers.set(el, this);
    return () => {
      providers.delete(el);
      this.el = void 0;
    };
  });
  static {
    setComponentTemplate(precompileTemplate("\n    <span hidden data-choreo-block {{this.mark}}>{{yield}}</span>\n  ", {
      strictMode: true
    }), this);
  }
};
var Sequence = class extends BlockComponent {
  kind = "sequence";
};
var Parallel = class extends BlockComponent {
  kind = "parallel";
};

// dist/layout-group.js
import Component2 from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { consumeTag, VOLATILE_TAG } from "@glimmer/validator";
import { modifier as modifier3 } from "ember-modifier";

// dist/scheduler.js
var impl;
function setPostRender(fn3) {
  impl = fn3;
}
function postRender(fn3) {
  if (!impl) {
    throw new Error("motion: no postRender scheduler installed (import the host adapter first)");
  }
  impl(fn3);
}

// dist/layout.js
var nodes = /* @__PURE__ */ new Set();
var hasTakenAnySnapshot = false;
function registerProjection(node) {
  nodes.add(node);
  return () => nodes.delete(node);
}
function snapshotAll() {
  hasTakenAnySnapshot = true;
  nodes.forEach((n) => n.willUpdate());
}
var flushMounts = () => {
};
function setMountFlusher(fn3) {
  flushMounts = fn3;
}
var settlePending = false;
registerBusyProbe(() => settlePending && "projection settle pending");
var BURST_LIMIT = 60;
var isDev = () => typeof process === "undefined" || true;
var burst = 0;
var frameBooked = false;
var breakerTripped = false;
function bookFrameReset() {
  if (frameBooked || typeof requestAnimationFrame !== "function") {
    return;
  }
  frameBooked = true;
  requestAnimationFrame(() => {
    frameBooked = false;
    burst = 0;
  });
}
function layoutLoopDetected() {
  return breakerTripped;
}
function resetLayoutLoopGuard() {
  breakerTripped = false;
  burst = 0;
}
function requestSettle() {
  if (settlePending) {
    return;
  }
  settlePending = true;
  bookFrameReset();
  burst += 1;
  if (burst <= BURST_LIMIT || typeof requestAnimationFrame !== "function") {
    postRender(settleNow);
    return;
  }
  breakerTripped = true;
  if (isDev()) {
    warnOnce(false, `glimmer-motion: ${BURST_LIMIT} layout settles without a single animation frame. Something is re-rendering a motion element in a loop. The usual cause is a @tracked property assigned unconditionally from a per-frame callback \u2014 an onDrag, onScroll or onViewportEnter handler \u2014 because a tracked property has no equality check and assigning the value it already holds still invalidates every consumer. Assign only on change. Settles are being deferred to animation frames so the page keeps responding; without that the tab would stop entirely.`);
  }
  requestAnimationFrame(() => postRender(settleNow));
}
var afterSettleQueue = [];
function afterSettle(fn3) {
  afterSettleQueue.push(fn3);
  requestSettle();
}
function settleNow() {
  settlePending = false;
  flushMounts();
  settleAll();
  if (afterSettleQueue.length) {
    const fns = afterSettleQueue.splice(0);
    microtask.postRender(() => fns.forEach((fn3) => fn3()));
  }
}
function settleAll() {
  const roots = /* @__PURE__ */ new Set();
  nodes.forEach((n) => roots.add(n.root ?? n));
  roots.forEach((r) => r.didUpdate());
}
function layoutChange(fn3) {
  snapshotAll();
  const out = fn3();
  requestSettle();
  return out;
}
function instantLayoutTransition(callback) {
  const root = rootProjectionNode.current;
  if (!root) {
    callback?.();
    return;
  }
  root.isUpdating = false;
  root.blockUpdate();
  callback?.();
}

// dist/layout-group.js
import { precompileTemplate as precompileTemplate2 } from "@ember/template-compilation";
import { setComponentTemplate as setComponentTemplate2 } from "@ember/component";

// ../../node_modules/.pnpm/decorator-transforms@2.4.0_@babel+core@7.29.7/node_modules/decorator-transforms/dist/runtime--fcdnjmJ.js
var deferred = /* @__PURE__ */ new WeakMap();
function deferDecorator(proto, prop, desc) {
  let map = deferred.get(proto);
  if (!map) {
    map = /* @__PURE__ */ new Map();
    deferred.set(proto, map);
  }
  map.set(prop, desc);
}
function findDeferredDecorator(target, prop) {
  var _a;
  let cursor = target.prototype;
  while (cursor) {
    let desc = (_a = deferred.get(cursor)) == null ? void 0 : _a.get(prop);
    if (desc) {
      return desc;
    }
    cursor = Object.getPrototypeOf(cursor);
  }
}
function decorateFieldV2(prototype, prop, decorators, initializer) {
  let desc = {
    configurable: true,
    enumerable: true,
    writable: true,
    initializer: null
  };
  if (initializer) {
    desc.initializer = initializer;
  }
  for (let decorator of decorators) {
    desc = decorator(prototype, prop, desc) || desc;
  }
  if (desc.initializer === void 0) {
    Object.defineProperty(prototype, prop, desc);
  } else {
    deferDecorator(prototype, prop, desc);
  }
}
function initializeDeferredDecorator(target, prop) {
  let desc = findDeferredDecorator(target.constructor, prop);
  if (desc) {
    Object.defineProperty(target, prop, {
      enumerable: desc.enumerable,
      configurable: desc.configurable,
      writable: desc.writable,
      value: desc.initializer ? desc.initializer.call(target) : void 0
    });
  }
}

// dist/layout-group.js
var groups = /* @__PURE__ */ new WeakMap();
function closestLayoutGroup(el) {
  const host = el.parentElement?.closest("[data-layout-group]");
  return host ? groups.get(host)?.context : void 0;
}
var pending = false;
function settleOnce() {
  pending = false;
  requestSettle();
}
function snapshotOnRender() {
  if (!pending) {
    pending = true;
    snapshotAll();
    postRender(settleOnce);
  }
}
var LayoutGroup = class extends Component2 {
  static {
    decorateFieldV2(this.prototype, "element", [tracked]);
  }
  #element = (initializeDeferredDecorator(this, "element"), void 0);
  static {
    decorateFieldV2(this.prototype, "version", [tracked], function() {
      return 0;
    });
  }
  #version = (initializeDeferredDecorator(this, "version"), void 0);
  ownGroup = nodeGroup();
  context;
  constructor(owner, args) {
    super(owner, args);
    const group = this;
    this.context = {
      get id() {
        return group.effectiveId;
      },
      get group() {
        return group.effectiveGroup;
      },
      forceRender: () => frame.postRender(() => {
        group.version++;
      })
    };
  }
  get inherit() {
    return this.args.inherit ?? true;
  }
  get parent() {
    return this.element ? closestLayoutGroup(this.element) : void 0;
  }
  /** id composition: upstream-id + "-" + own id, or the upstream id when we have none (only when inheriting) */
  get effectiveId() {
    const own = this.args.id;
    const upstream = this.inherit === true || this.inherit === "id" ? this.parent?.id : void 0;
    if (upstream) {
      return own ? `${upstream}-${own}` : upstream;
    }
    return own;
  }
  get effectiveGroup() {
    return this.inherit === true && this.parent?.group || this.ownGroup;
  }
  register = modifier3((el) => {
    groups.set(el, this);
    this.element = el;
    return () => groups.delete(el);
  });
  get renderDetector() {
    consumeTag(VOLATILE_TAG);
    void this.version;
    snapshotOnRender();
    return void 0;
  }
  static {
    setComponentTemplate2(precompileTemplate2('\n    {{this.renderDetector}}\n    <div data-layout-group style="display: contents" {{this.register}}>\n      {{yield this.context}}\n    </div>\n  ', {
      strictMode: true
    }), this);
  }
};

// dist/gestures/event-info.js
function extractEventInfo(event) {
  return {
    point: {
      x: event.pageX,
      y: event.pageY
    }
  };
}
var addPointerInfo = (handler) => (event) => isPrimaryPointer(event) && handler(event, extractEventInfo(event));

// dist/gestures/add-pointer-event.js
function addPointerEvent(target, eventName, handler, options) {
  return addDomEvent(target, eventName, addPointerInfo(handler), options);
}

// dist/gestures/constraints.js
function applyConstraints(point2, {
  min,
  max
}, elastic) {
  if (min !== void 0 && point2 < min) {
    point2 = elastic ? mixNumber(min, point2, elastic.min) : Math.max(point2, min);
  } else if (max !== void 0 && point2 > max) {
    point2 = elastic ? mixNumber(max, point2, elastic.max) : Math.min(point2, max);
  }
  return point2;
}
function calcRelativeAxisConstraints(axis, min, max) {
  return {
    min: min !== void 0 ? axis.min + min : void 0,
    max: max !== void 0 ? axis.max + max - (axis.max - axis.min) : void 0
  };
}
function calcRelativeConstraints(layoutBox, {
  top,
  left,
  bottom,
  right
}) {
  return {
    x: calcRelativeAxisConstraints(layoutBox.x, left, right),
    y: calcRelativeAxisConstraints(layoutBox.y, top, bottom)
  };
}
function calcViewportAxisConstraints(layoutAxis, constraintsAxis) {
  let min = constraintsAxis.min - layoutAxis.min;
  let max = constraintsAxis.max - layoutAxis.max;
  if (constraintsAxis.max - constraintsAxis.min < layoutAxis.max - layoutAxis.min) {
    [min, max] = [max, min];
  }
  return {
    min,
    max
  };
}
function calcViewportConstraints(layoutBox, constraintsBox) {
  return {
    x: calcViewportAxisConstraints(layoutBox.x, constraintsBox.x),
    y: calcViewportAxisConstraints(layoutBox.y, constraintsBox.y)
  };
}
function calcOrigin(source, target) {
  let origin = 0.5;
  const sourceLength = calcLength(source);
  const targetLength = calcLength(target);
  if (targetLength > sourceLength) {
    origin = progress(target.min, target.max - sourceLength, source.min);
  } else if (sourceLength > targetLength) {
    origin = progress(source.min, source.max - targetLength, target.min);
  }
  return clamp(0, 1, origin);
}
function rebaseAxisConstraints(layout, constraints) {
  const relativeConstraints = {};
  if (constraints.min !== void 0) {
    relativeConstraints.min = constraints.min - layout.min;
  }
  if (constraints.max !== void 0) {
    relativeConstraints.max = constraints.max - layout.min;
  }
  return relativeConstraints;
}
var defaultElastic = 0.35;
function resolveDragElastic(dragElastic = defaultElastic) {
  if (dragElastic === false) {
    dragElastic = 0;
  } else if (dragElastic === true) {
    dragElastic = defaultElastic;
  }
  return {
    x: resolveAxisElastic(dragElastic, "left", "right"),
    y: resolveAxisElastic(dragElastic, "top", "bottom")
  };
}
function resolveAxisElastic(dragElastic, minLabel, maxLabel) {
  return {
    min: resolvePointElastic(dragElastic, minLabel),
    max: resolvePointElastic(dragElastic, maxLabel)
  };
}
function resolvePointElastic(dragElastic, label) {
  return typeof dragElastic === "number" ? dragElastic : dragElastic[label] || 0;
}

// dist/gestures/get-context-window.js
var getContextWindow = ({
  current: current2
}) => {
  return current2 ? current2.ownerDocument.defaultView : null;
};

// dist/gestures/is-ref-object.js
function isRefObject(ref) {
  return ref && typeof ref === "object" && Object.prototype.hasOwnProperty.call(ref, "current");
}

// dist/gestures/lock-select.js
var locks = 0;
var onSelectStart = null;
function lockTextSelect() {
  locks += 1;
  if (locks !== 1) {
    return;
  }
  const root = document.documentElement;
  root.dataset.gmDragging = "";
  root.style.setProperty("user-select", "none");
  root.style.setProperty("-webkit-user-select", "none");
  window.getSelection()?.removeAllRanges();
  onSelectStart = (event) => event.preventDefault();
  document.addEventListener("selectstart", onSelectStart, true);
}
function unlockTextSelect() {
  locks = Math.max(0, locks - 1);
  if (locks !== 0) {
    return;
  }
  const root = document.documentElement;
  delete root.dataset.gmDragging;
  root.style.removeProperty("user-select");
  root.style.removeProperty("-webkit-user-select");
  if (onSelectStart) {
    document.removeEventListener("selectstart", onSelectStart, true);
    onSelectStart = null;
  }
}

// dist/gestures/distance.js
var distance = (a, b) => Math.abs(a - b);
function distance2D(a, b) {
  const xDelta = distance(a.x, b.x);
  const yDelta = distance(a.y, b.y);
  return Math.sqrt(xDelta ** 2 + yDelta ** 2);
}

// dist/gestures/pan-session.js
var overflowStyles = /* @__PURE__ */ new Set(["auto", "scroll"]);
var PanSession = class {
  /**
   * @internal
   */
  history;
  /**
   * @internal
   */
  startEvent = null;
  /**
   * @internal
   */
  lastMoveEvent = null;
  /**
   * @internal
   */
  lastMoveEventInfo = null;
  /**
   * Raw (untransformed) event info, re-transformed each frame
   * so transformPagePoint sees the current parent matrix.
   * @internal
   */
  lastRawMoveEventInfo = null;
  /**
   * @internal
   */
  transformPagePoint;
  /**
   * @internal
   */
  handlers = {};
  /**
   * @internal
   */
  removeListeners;
  /**
   * For determining if an animation should resume after it is interupted
   *
   * @internal
   */
  dragSnapToOrigin;
  /**
   * The distance after which panning should start.
   *
   * @internal
   */
  distanceThreshold;
  /**
   * @internal
   */
  contextWindow = window;
  /**
   * Scroll positions of scrollable ancestors and window.
   * @internal
   */
  scrollPositions = /* @__PURE__ */ new Map();
  /**
   * Cleanup function for scroll listeners.
   * @internal
   */
  removeScrollListeners = null;
  constructor(event, handlers, {
    transformPagePoint,
    contextWindow = window,
    dragSnapToOrigin = false,
    distanceThreshold = 3,
    element
  } = {}) {
    if (!isPrimaryPointer(event)) {
      return;
    }
    this.dragSnapToOrigin = dragSnapToOrigin;
    this.handlers = handlers;
    this.transformPagePoint = transformPagePoint;
    this.distanceThreshold = distanceThreshold;
    this.contextWindow = contextWindow || window;
    const info = extractEventInfo(event);
    const initialInfo = transformPoint(info, this.transformPagePoint);
    const {
      point: point2
    } = initialInfo;
    const {
      timestamp
    } = frameData;
    this.history = [{
      ...point2,
      timestamp
    }];
    const {
      onSessionStart
    } = handlers;
    onSessionStart && onSessionStart(event, getPanInfo(initialInfo, this.history));
    const eventOptions = {
      passive: true,
      capture: true
    };
    this.removeListeners = pipe(addPointerEvent(this.contextWindow, "pointermove", this.handlePointerMove, eventOptions), addPointerEvent(this.contextWindow, "pointerup", this.handlePointerUp, eventOptions), addPointerEvent(this.contextWindow, "pointercancel", this.handlePointerUp, eventOptions));
    if (element) {
      this.startScrollTracking(element);
    }
  }
  /**
   * Start tracking scroll on ancestors and window.
   */
  startScrollTracking(element) {
    let current2 = element.parentElement;
    while (current2) {
      const style2 = getComputedStyle(current2);
      if (overflowStyles.has(style2.overflowX) || overflowStyles.has(style2.overflowY)) {
        this.scrollPositions.set(current2, {
          x: current2.scrollLeft,
          y: current2.scrollTop
        });
      }
      current2 = current2.parentElement;
    }
    this.scrollPositions.set(window, {
      x: window.scrollX,
      y: window.scrollY
    });
    window.addEventListener("scroll", this.onElementScroll, {
      capture: true
    });
    window.addEventListener("scroll", this.onWindowScroll);
    this.removeScrollListeners = () => {
      window.removeEventListener("scroll", this.onElementScroll, {
        capture: true
      });
      window.removeEventListener("scroll", this.onWindowScroll);
    };
  }
  onElementScroll = (event) => {
    this.handleScroll(event.target);
  };
  onWindowScroll = () => {
    this.handleScroll(window);
  };
  /**
   * Handle scroll compensation during drag.
   *
   * For element scroll: adjusts history origin since pageX/pageY doesn't change.
   * For window scroll: adjusts lastMoveEventInfo since pageX/pageY would change.
   */
  handleScroll(target) {
    const initial = this.scrollPositions.get(target);
    if (!initial) {
      return;
    }
    const isWindow = target === window;
    const current2 = isWindow ? {
      x: window.scrollX,
      y: window.scrollY
    } : {
      x: target.scrollLeft,
      y: target.scrollTop
    };
    const delta = {
      x: current2.x - initial.x,
      y: current2.y - initial.y
    };
    if (delta.x === 0 && delta.y === 0) {
      return;
    }
    if (isWindow) {
      if (this.lastMoveEventInfo) {
        this.lastMoveEventInfo.point.x += delta.x;
        this.lastMoveEventInfo.point.y += delta.y;
      }
    } else {
      if (this.history.length > 0) {
        this.history[0].x -= delta.x;
        this.history[0].y -= delta.y;
      }
    }
    this.scrollPositions.set(target, current2);
    frame.update(this.updatePoint, true);
  }
  updatePoint = () => {
    if (!(this.lastMoveEvent && this.lastMoveEventInfo)) {
      return;
    }
    if (this.lastRawMoveEventInfo) {
      this.lastMoveEventInfo = transformPoint(this.lastRawMoveEventInfo, this.transformPagePoint);
    }
    const info = getPanInfo(this.lastMoveEventInfo, this.history);
    const isPanStarted = this.startEvent !== null;
    const isDistancePastThreshold = distance2D(info.offset, {
      x: 0,
      y: 0
    }) >= this.distanceThreshold;
    if (!isPanStarted && !isDistancePastThreshold) {
      return;
    }
    const {
      point: point2
    } = info;
    const {
      timestamp
    } = frameData;
    this.history.push({
      ...point2,
      timestamp
    });
    const {
      onStart,
      onMove
    } = this.handlers;
    if (!isPanStarted) {
      onStart && onStart(this.lastMoveEvent, info);
      this.startEvent = this.lastMoveEvent;
    }
    onMove && onMove(this.lastMoveEvent, info);
  };
  handlePointerMove = (event, info) => {
    this.lastMoveEvent = event;
    this.lastRawMoveEventInfo = info;
    this.lastMoveEventInfo = transformPoint(info, this.transformPagePoint);
    frame.update(this.updatePoint, true);
  };
  handlePointerUp = (event, info) => {
    this.end();
    const {
      onEnd,
      onSessionEnd,
      resumeAnimation
    } = this.handlers;
    if (this.dragSnapToOrigin || !this.startEvent) {
      resumeAnimation && resumeAnimation();
    }
    if (!(this.lastMoveEvent && this.lastMoveEventInfo)) {
      return;
    }
    const panInfo = getPanInfo(event.type === "pointercancel" ? this.lastMoveEventInfo : transformPoint(info, this.transformPagePoint), this.history);
    if (this.startEvent && onEnd) {
      onEnd(event, panInfo);
    }
    onSessionEnd && onSessionEnd(event, panInfo);
  };
  updateHandlers(handlers) {
    this.handlers = handlers;
  }
  end() {
    this.removeListeners && this.removeListeners();
    this.removeScrollListeners && this.removeScrollListeners();
    this.scrollPositions.clear();
    cancelFrame(this.updatePoint);
  }
};
function transformPoint(info, transformPagePoint) {
  return transformPagePoint ? {
    point: transformPagePoint(info.point)
  } : info;
}
function subtractPoint(a, b) {
  return {
    x: a.x - b.x,
    y: a.y - b.y
  };
}
function getPanInfo({
  point: point2
}, history) {
  return {
    point: point2,
    delta: subtractPoint(point2, lastDevicePoint(history)),
    offset: subtractPoint(point2, startDevicePoint(history)),
    velocity: getVelocity(history, 0.1)
  };
}
function startDevicePoint(history) {
  return history[0];
}
function lastDevicePoint(history) {
  return history[history.length - 1];
}
function getVelocity(history, timeDelta) {
  if (history.length < 2) {
    return {
      x: 0,
      y: 0
    };
  }
  let i = history.length - 1;
  let timestampedPoint = null;
  const lastPoint = lastDevicePoint(history);
  while (i >= 0) {
    timestampedPoint = history[i];
    if (lastPoint.timestamp - timestampedPoint.timestamp > secondsToMilliseconds(timeDelta)) {
      break;
    }
    i--;
  }
  if (!timestampedPoint) {
    return {
      x: 0,
      y: 0
    };
  }
  if (timestampedPoint === history[0] && history.length > 2 && lastPoint.timestamp - timestampedPoint.timestamp > secondsToMilliseconds(timeDelta) * 2) {
    timestampedPoint = history[1];
  }
  const time2 = millisecondsToSeconds(lastPoint.timestamp - timestampedPoint.timestamp);
  if (time2 === 0) {
    return {
      x: 0,
      y: 0
    };
  }
  const currentVelocity = {
    x: (lastPoint.x - timestampedPoint.x) / time2,
    y: (lastPoint.y - timestampedPoint.y) / time2
  };
  if (currentVelocity.x === Infinity) {
    currentVelocity.x = 0;
  }
  if (currentVelocity.y === Infinity) {
    currentVelocity.y = 0;
  }
  return currentVelocity;
}

// dist/gestures/visual-element-drag-controls.js
var elementDragControls = /* @__PURE__ */ new WeakMap();
var VisualElementDragControls = class {
  visualElement;
  panSession;
  openDragLock = null;
  isDragging = false;
  currentDirection = null;
  originPoint = {
    x: 0,
    y: 0
  };
  /**
   * The permitted boundaries of travel, in pixels.
   */
  constraints = false;
  hasMutatedConstraints = false;
  /**
   * The per-axis resolved elastic values.
   */
  elastic = createBox();
  /**
   * The latest pointer event. Used as fallback when the `cancel` and `stop` functions are called without arguments.
   */
  latestPointerEvent = null;
  /**
   * The latest pan info. Used as fallback when the `cancel` and `stop` functions are called without arguments.
   */
  latestPanInfo = null;
  /**
   * True while a pan session has locked document text selection.
   */
  selectLocked = false;
  constructor(visualElement) {
    this.visualElement = visualElement;
  }
  start(originEvent, {
    snapToCursor = false,
    distanceThreshold
  } = {}) {
    const {
      presenceContext
    } = this.visualElement;
    if (presenceContext && presenceContext.isPresent === false) {
      return;
    }
    const onSessionStart = (event) => {
      this.lockSelect();
      if (snapToCursor) {
        this.snapToCursor(extractEventInfo(event).point);
      }
      this.stopAnimation();
    };
    const onStart = (event, info) => {
      const {
        drag,
        dragPropagation,
        onDragStart
      } = this.getProps();
      if (drag && !dragPropagation) {
        if (this.openDragLock) {
          this.openDragLock();
        }
        this.openDragLock = setDragLock(drag);
        if (!this.openDragLock) {
          return;
        }
      }
      this.latestPointerEvent = event;
      this.latestPanInfo = info;
      this.isDragging = true;
      this.currentDirection = null;
      this.resolveConstraints();
      if (this.visualElement.projection) {
        this.visualElement.projection.isAnimationBlocked = true;
        this.visualElement.projection.target = void 0;
      }
      eachAxis((axis) => {
        let current2 = this.getAxisMotionValue(axis).get() || 0;
        if (percent.test(current2)) {
          const {
            projection
          } = this.visualElement;
          if (projection && projection.layout) {
            const measuredAxis = projection.layout.layoutBox[axis];
            if (measuredAxis) {
              const length = calcLength(measuredAxis);
              current2 = length * (parseFloat(current2) / 100);
            }
          }
        }
        this.originPoint[axis] = current2;
      });
      if (onDragStart) {
        frame.update(() => onDragStart(event, info), false, true);
      }
      addValueToWillChange(this.visualElement, "transform");
      const {
        animationState
      } = this.visualElement;
      animationState && animationState.setActive("whileDrag", true);
    };
    const onMove = (event, info) => {
      this.latestPointerEvent = event;
      this.latestPanInfo = info;
      const {
        dragPropagation,
        dragDirectionLock,
        onDirectionLock,
        onDrag
      } = this.getProps();
      if (!dragPropagation && !this.openDragLock) {
        return;
      }
      const {
        offset
      } = info;
      if (dragDirectionLock && this.currentDirection === null) {
        this.currentDirection = getCurrentDirection(offset);
        if (this.currentDirection !== null) {
          onDirectionLock && onDirectionLock(this.currentDirection);
        }
        return;
      }
      this.updateAxis("x", info.point, offset);
      this.updateAxis("y", info.point, offset);
      this.visualElement.render();
      if (onDrag) {
        frame.update(() => onDrag(event, info), false, true);
      }
    };
    const onSessionEnd = (event, info) => {
      this.latestPointerEvent = event;
      this.latestPanInfo = info;
      this.stop(event, info);
      this.latestPointerEvent = null;
      this.latestPanInfo = null;
    };
    const resumeAnimation = () => {
      const {
        dragSnapToOrigin: snap
      } = this.getProps();
      if (snap || this.constraints) {
        this.startAnimation({
          x: 0,
          y: 0
        });
      }
    };
    const {
      dragSnapToOrigin
    } = this.getProps();
    this.panSession = new PanSession(originEvent, {
      onSessionStart,
      onStart,
      onMove,
      onSessionEnd,
      resumeAnimation
    }, {
      transformPagePoint: this.visualElement.getTransformPagePoint(),
      dragSnapToOrigin,
      distanceThreshold,
      contextWindow: getContextWindow(this.visualElement),
      element: this.visualElement.current
    });
  }
  /**
   * @internal
   */
  stop(event, panInfo) {
    const finalEvent = event || this.latestPointerEvent;
    const finalPanInfo = panInfo || this.latestPanInfo;
    const isDragging2 = this.isDragging;
    this.cancel();
    if (!isDragging2 || !finalPanInfo || !finalEvent) {
      return;
    }
    const {
      velocity
    } = finalPanInfo;
    this.startAnimation(velocity);
    const {
      onDragEnd
    } = this.getProps();
    if (onDragEnd) {
      frame.postRender(() => onDragEnd(finalEvent, finalPanInfo));
    }
  }
  /**
   * @internal
   */
  cancel() {
    this.isDragging = false;
    const {
      projection,
      animationState
    } = this.visualElement;
    if (projection) {
      projection.isAnimationBlocked = false;
    }
    this.endPanSession();
    const {
      dragPropagation
    } = this.getProps();
    if (!dragPropagation && this.openDragLock) {
      this.openDragLock();
      this.openDragLock = null;
    }
    animationState && animationState.setActive("whileDrag", false);
  }
  /**
   * Clean up the pan session without modifying other drag state.
   * This is used during unmount to ensure event listeners are removed
   * without affecting projection animations or drag locks.
   * @internal
   */
  endPanSession() {
    this.panSession && this.panSession.end();
    this.panSession = void 0;
    this.unlockSelect();
  }
  lockSelect() {
    if (this.selectLocked) {
      return;
    }
    this.selectLocked = true;
    lockTextSelect();
  }
  unlockSelect() {
    if (!this.selectLocked) {
      return;
    }
    this.selectLocked = false;
    unlockTextSelect();
  }
  updateAxis(axis, _point, offset) {
    const {
      drag
    } = this.getProps();
    if (!offset || !shouldDrag(axis, drag, this.currentDirection)) {
      return;
    }
    const axisValue = this.getAxisMotionValue(axis);
    let next2 = this.originPoint[axis] + offset[axis];
    if (this.constraints && this.constraints[axis]) {
      next2 = applyConstraints(next2, this.constraints[axis], this.elastic[axis]);
    }
    axisValue.set(next2);
  }
  resolveConstraints() {
    const {
      dragConstraints,
      dragElastic
    } = this.getProps();
    const layout = this.visualElement.projection && !this.visualElement.projection.layout ? this.visualElement.projection.measure(false) : this.visualElement.projection?.layout;
    const prevConstraints = this.constraints;
    if (dragConstraints && isRefObject(dragConstraints)) {
      if (!this.constraints) {
        this.constraints = this.resolveRefConstraints();
      }
    } else {
      if (dragConstraints && layout) {
        this.constraints = calcRelativeConstraints(layout.layoutBox, dragConstraints);
      } else {
        this.constraints = false;
      }
    }
    this.elastic = resolveDragElastic(dragElastic);
    if (prevConstraints !== this.constraints && !isRefObject(dragConstraints) && layout && this.constraints && !this.hasMutatedConstraints) {
      eachAxis((axis) => {
        if (this.constraints !== false && this.getAxisMotionValue(axis)) {
          this.constraints[axis] = rebaseAxisConstraints(layout.layoutBox[axis], this.constraints[axis]);
        }
      });
    }
  }
  resolveRefConstraints() {
    const {
      dragConstraints: constraints,
      onMeasureDragConstraints
    } = this.getProps();
    if (!constraints || !isRefObject(constraints)) {
      return false;
    }
    const constraintsElement = constraints.current;
    invariant(constraintsElement !== null, "If `dragConstraints` is set as a React ref, that ref must be passed to another component's `ref` prop.", "drag-constraints-ref");
    const {
      projection
    } = this.visualElement;
    if (!projection || !projection.layout) {
      return false;
    }
    if (projection.root) {
      projection.root.scroll = void 0;
      projection.root.updateScroll();
    }
    const constraintsBox = measurePageBox(constraintsElement, projection.root, this.visualElement.getTransformPagePoint());
    let measuredConstraints = calcViewportConstraints(projection.layout.layoutBox, constraintsBox);
    if (onMeasureDragConstraints) {
      const userConstraints = onMeasureDragConstraints(convertBoxToBoundingBox(measuredConstraints));
      this.hasMutatedConstraints = !!userConstraints;
      if (userConstraints) {
        measuredConstraints = convertBoundingBoxToBox(userConstraints);
      }
    }
    return measuredConstraints;
  }
  startAnimation(velocity) {
    const {
      drag,
      dragMomentum,
      dragElastic,
      dragTransition,
      dragSnapToOrigin,
      onDragTransitionEnd
    } = this.getProps();
    const constraints = this.constraints || {};
    const momentumAnimations = eachAxis((axis) => {
      if (!shouldDrag(axis, drag, this.currentDirection)) {
        return;
      }
      let transition = constraints && constraints[axis] || {};
      if (dragSnapToOrigin === true || dragSnapToOrigin === axis) {
        transition = {
          min: 0,
          max: 0
        };
      }
      const bounceStiffness = dragElastic ? 200 : 1e6;
      const bounceDamping = dragElastic ? 40 : 1e7;
      const inertia3 = {
        type: "inertia",
        velocity: dragMomentum ? velocity[axis] : 0,
        bounceStiffness,
        bounceDamping,
        timeConstant: 750,
        restDelta: 1,
        restSpeed: 10,
        ...dragTransition,
        ...transition
      };
      return this.startAxisValueAnimation(axis, inertia3);
    });
    return Promise.all(momentumAnimations).then(onDragTransitionEnd);
  }
  startAxisValueAnimation(axis, transition) {
    const axisValue = this.getAxisMotionValue(axis);
    addValueToWillChange(this.visualElement, axis);
    return axisValue.start(animateMotionValue(axis, axisValue, 0, transition, this.visualElement, false));
  }
  stopAnimation() {
    eachAxis((axis) => this.getAxisMotionValue(axis).stop());
  }
  /**
   * Drag works differently depending on which props are provided.
   *
   * - If _dragX and _dragY are provided, we output the gesture delta directly to those motion values.
   * - Otherwise, we apply the delta to the x/y motion values.
   */
  getAxisMotionValue(axis) {
    const dragKey = `_drag${axis.toUpperCase()}`;
    const props = this.visualElement.getProps();
    const externalMotionValue = props[dragKey];
    return externalMotionValue ? externalMotionValue : this.visualElement.getValue(axis, this.visualElement.latestValues[axis] ?? 0);
  }
  snapToCursor(point2) {
    eachAxis((axis) => {
      const {
        drag
      } = this.getProps();
      if (!shouldDrag(axis, drag, this.currentDirection)) {
        return;
      }
      const {
        projection
      } = this.visualElement;
      const axisValue = this.getAxisMotionValue(axis);
      if (projection && projection.layout) {
        const {
          min,
          max
        } = projection.layout.layoutBox[axis];
        const current2 = axisValue.get() || 0;
        axisValue.set(point2[axis] - mixNumber(min, max, 0.5) + current2);
      }
    });
  }
  /**
   * When the viewport resizes we want to check if the measured constraints
   * have changed and, if so, reposition the element within those new constraints
   * relative to where it was before the resize.
   */
  scalePositionWithinConstraints() {
    if (!this.visualElement.current) {
      return;
    }
    const {
      drag,
      dragConstraints
    } = this.getProps();
    const {
      projection
    } = this.visualElement;
    if (!isRefObject(dragConstraints) || !projection || !this.constraints) {
      return;
    }
    this.stopAnimation();
    const boxProgress = {
      x: 0,
      y: 0
    };
    eachAxis((axis) => {
      const axisValue = this.getAxisMotionValue(axis);
      if (axisValue && this.constraints !== false) {
        const latest = axisValue.get();
        boxProgress[axis] = calcOrigin({
          min: latest,
          max: latest
        }, this.constraints[axis]);
      }
    });
    const {
      transformTemplate
    } = this.visualElement.getProps();
    this.visualElement.current.style.transform = transformTemplate ? transformTemplate({}, "") : "none";
    projection.root && projection.root.updateScroll();
    projection.updateLayout();
    this.constraints = false;
    this.resolveConstraints();
    eachAxis((axis) => {
      if (!shouldDrag(axis, drag, null)) {
        return;
      }
      const axisValue = this.getAxisMotionValue(axis);
      const {
        min,
        max
      } = this.constraints[axis];
      axisValue.set(mixNumber(min, max, boxProgress[axis]));
    });
    this.visualElement.render();
  }
  addListeners() {
    if (!this.visualElement.current) {
      return;
    }
    elementDragControls.set(this.visualElement, this);
    const element = this.visualElement.current;
    const stopPointerListener = addPointerEvent(element, "pointerdown", (event) => {
      const {
        drag,
        dragListener = true
      } = this.getProps();
      const target = event.target;
      const isClickingTextInputChild = target !== element && isElementTextInput(target);
      if (drag && dragListener && !isClickingTextInputChild) {
        this.start(event);
      }
    });
    let stopResizeObservers;
    const measureDragConstraints = () => {
      const {
        dragConstraints
      } = this.getProps();
      if (isRefObject(dragConstraints) && dragConstraints.current) {
        this.constraints = this.resolveRefConstraints();
        if (!stopResizeObservers) {
          stopResizeObservers = startResizeObservers(element, dragConstraints.current, () => this.scalePositionWithinConstraints());
        }
      }
    };
    const {
      projection
    } = this.visualElement;
    const stopMeasureLayoutListener = projection.addEventListener("measure", measureDragConstraints);
    if (projection && !projection.layout) {
      projection.root && projection.root.updateScroll();
      projection.updateLayout();
    }
    frame.read(measureDragConstraints);
    const stopResizeListener = addDomEvent(window, "resize", () => this.scalePositionWithinConstraints());
    const stopLayoutUpdateListener = projection.addEventListener("didUpdate", ({
      delta,
      hasLayoutChanged
    }) => {
      if (this.isDragging && hasLayoutChanged) {
        eachAxis((axis) => {
          const motionValue2 = this.getAxisMotionValue(axis);
          if (!motionValue2) {
            return;
          }
          this.originPoint[axis] += delta[axis].translate;
          motionValue2.set(motionValue2.get() + delta[axis].translate);
        });
        this.visualElement.render();
      }
    });
    return () => {
      stopResizeListener();
      stopPointerListener();
      stopMeasureLayoutListener();
      stopLayoutUpdateListener && stopLayoutUpdateListener();
      stopResizeObservers && stopResizeObservers();
    };
  }
  getProps() {
    const props = this.visualElement.getProps();
    const {
      drag = false,
      dragDirectionLock = false,
      dragPropagation = false,
      dragConstraints = false,
      dragElastic = defaultElastic,
      dragMomentum = true
    } = props;
    return {
      ...props,
      drag,
      dragDirectionLock,
      dragPropagation,
      dragConstraints,
      dragElastic,
      dragMomentum
    };
  }
};
function skipFirstCall(callback) {
  let isFirst = true;
  return () => {
    if (isFirst) {
      isFirst = false;
      return;
    }
    callback();
  };
}
function startResizeObservers(element, constraintsElement, onResize) {
  const stopElement = resize(element, skipFirstCall(onResize));
  const stopContainer = resize(constraintsElement, skipFirstCall(onResize));
  return () => {
    stopElement();
    stopContainer();
  };
}
function shouldDrag(direction, drag, currentDirection) {
  return (drag === true || drag === direction) && (currentDirection === null || currentDirection === direction);
}
function getCurrentDirection(offset, lockThreshold = 10) {
  let direction = null;
  if (Math.abs(offset.y) > lockThreshold) {
    direction = "y";
  } else if (Math.abs(offset.x) > lockThreshold) {
    direction = "x";
  }
  return direction;
}

// dist/gestures/drag-gesture.js
var DragGesture = class extends Feature {
  controls;
  removeGroupControls = noop;
  removeListeners = noop;
  constructor(node) {
    super(node);
    this.controls = new VisualElementDragControls(node);
  }
  mount() {
    const {
      dragControls
    } = this.node.getProps();
    if (dragControls) {
      this.removeGroupControls = dragControls.subscribe(this.controls);
    }
    this.removeListeners = this.controls.addListeners() || noop;
  }
  update() {
    const {
      dragControls
    } = this.node.getProps();
    const {
      dragControls: prevDragControls
    } = this.node.prevProps || {};
    if (dragControls !== prevDragControls) {
      this.removeGroupControls();
      if (dragControls) {
        this.removeGroupControls = dragControls.subscribe(this.controls);
      }
    }
  }
  unmount() {
    this.removeGroupControls();
    this.removeListeners();
    this.controls.cancel();
  }
};

// dist/gestures/focus.js
var FocusGesture = class extends Feature {
  isActive = false;
  onFocus() {
    let isFocusVisible = false;
    try {
      isFocusVisible = this.node.current.matches(":focus-visible");
    } catch (e) {
      isFocusVisible = true;
    }
    if (!isFocusVisible || !this.node.animationState) {
      return;
    }
    this.node.animationState.setActive("whileFocus", true);
    this.isActive = true;
  }
  onBlur() {
    if (!this.isActive || !this.node.animationState) {
      return;
    }
    this.node.animationState.setActive("whileFocus", false);
    this.isActive = false;
  }
  mount() {
    this.unmount = pipe(addDomEvent(this.node.current, "focus", () => this.onFocus()), addDomEvent(this.node.current, "blur", () => this.onBlur()));
  }
  unmount() {
  }
};

// dist/gestures/hover.js
function handleHoverEvent(node, event, lifecycle) {
  const {
    props
  } = node;
  if (node.animationState && props.whileHover) {
    node.animationState.setActive("whileHover", lifecycle === "Start");
  }
  const eventName = "onHover" + lifecycle;
  const callback = props[eventName];
  if (callback) {
    frame.postRender(() => callback(event, extractEventInfo(event)));
  }
}
var HoverGesture = class extends Feature {
  mount() {
    const {
      current: current2
    } = this.node;
    if (!current2) {
      return;
    }
    this.unmount = hover(current2, (_element, startEvent) => {
      handleHoverEvent(this.node, startEvent, "Start");
      return (endEvent) => handleHoverEvent(this.node, endEvent, "End");
    });
  }
  unmount() {
  }
};

// dist/gestures/pan-gesture.js
var asyncHandler = (handler) => (event, info) => {
  if (handler) {
    frame.update(() => handler(event, info), false, true);
  }
};
var PanGesture = class extends Feature {
  session;
  removePointerDownListener = noop;
  onPointerDown(pointerDownEvent) {
    this.session = new PanSession(pointerDownEvent, this.createPanHandlers(), {
      transformPagePoint: this.node.getTransformPagePoint(),
      contextWindow: getContextWindow(this.node)
    });
  }
  createPanHandlers() {
    const {
      onPanSessionStart,
      onPanStart,
      onPan,
      onPanEnd
    } = this.node.getProps();
    return {
      onSessionStart: asyncHandler(onPanSessionStart),
      onStart: asyncHandler(onPanStart),
      onMove: asyncHandler(onPan),
      onEnd: (event, info) => {
        delete this.session;
        if (onPanEnd) {
          frame.postRender(() => onPanEnd(event, info));
        }
      }
    };
  }
  mount() {
    this.removePointerDownListener = addPointerEvent(this.node.current, "pointerdown", (event) => this.onPointerDown(event));
  }
  update() {
    this.session && this.session.updateHandlers(this.createPanHandlers());
  }
  unmount() {
    this.removePointerDownListener();
    this.session && this.session.end();
  }
};

// dist/gestures/press.js
function handlePressEvent(node, event, lifecycle) {
  const {
    props
  } = node;
  if (node.current instanceof HTMLButtonElement && node.current.disabled) {
    return;
  }
  if (node.animationState && props.whileTap) {
    node.animationState.setActive("whileTap", lifecycle === "Start");
  }
  const eventName = "onTap" + (lifecycle === "End" ? "" : lifecycle);
  const callback = props[eventName];
  if (callback) {
    frame.postRender(() => callback(event, extractEventInfo(event)));
  }
}
var PressGesture = class extends Feature {
  mount() {
    const {
      current: current2
    } = this.node;
    if (!current2) {
      return;
    }
    const {
      globalTapTarget,
      propagate
    } = this.node.props;
    this.unmount = press(current2, (_element, startEvent) => {
      handlePressEvent(this.node, startEvent, "Start");
      return (endEvent, {
        success
      }) => handlePressEvent(this.node, endEvent, success ? "End" : "Cancel");
    }, {
      useGlobalTarget: globalTapTarget,
      stopPropagation: propagate?.tap === false
    });
  }
  unmount() {
  }
};

// dist/gestures/viewport.js
var thresholdNames = {
  some: 0,
  all: 1
};
var InViewFeature = class extends Feature {
  hasEnteredView = false;
  isInView = false;
  stopObserver;
  startObserver() {
    this.stopObserver?.();
    const {
      viewport = {}
    } = this.node.getProps();
    const {
      root,
      margin: rootMargin,
      amount = "some",
      once
    } = viewport;
    const options = {
      root: root ? root.current : void 0,
      rootMargin,
      threshold: typeof amount === "number" ? amount : thresholdNames[amount]
    };
    const onIntersectionUpdate = (entry) => {
      const {
        isIntersecting
      } = entry;
      if (this.isInView === isIntersecting) {
        return;
      }
      this.isInView = isIntersecting;
      if (once && !isIntersecting && this.hasEnteredView) {
        return;
      } else if (isIntersecting) {
        this.hasEnteredView = true;
      }
      if (this.node.animationState) {
        this.node.animationState.setActive("whileInView", isIntersecting);
      }
      const {
        onViewportEnter,
        onViewportLeave
      } = this.node.getProps();
      const callback = isIntersecting ? onViewportEnter : onViewportLeave;
      callback && callback(entry);
    };
    this.stopObserver = observeIntersection(this.node.current, options, onIntersectionUpdate);
  }
  mount() {
    this.startObserver();
  }
  update() {
    if (typeof IntersectionObserver === "undefined") {
      return;
    }
    const {
      props,
      prevProps
    } = this.node;
    const hasOptionsChanged = ["amount", "margin", "root"].some(hasViewportOptionChanged(props, prevProps));
    if (hasOptionsChanged) {
      this.startObserver();
    }
  }
  unmount() {
    this.stopObserver?.();
    this.hasEnteredView = false;
    this.isInView = false;
  }
};
function hasViewportOptionChanged({
  viewport = {}
}, {
  viewport: prevViewport = {}
} = {}) {
  return (name) => viewport[name] !== prevViewport[name];
}
var observerCallbacks = /* @__PURE__ */ new WeakMap();
var observers = /* @__PURE__ */ new WeakMap();
var fireObserverCallback = (entry) => {
  const callback = observerCallbacks.get(entry.target);
  callback && callback(entry);
};
var fireAllObserverCallbacks = (entries) => {
  entries.forEach(fireObserverCallback);
};
function initIntersectionObserver({
  root,
  ...options
}) {
  const lookupRoot = root || document;
  if (!observers.has(lookupRoot)) {
    observers.set(lookupRoot, {});
  }
  const rootObservers = observers.get(lookupRoot);
  const key = JSON.stringify(options);
  if (!rootObservers[key]) {
    rootObservers[key] = new IntersectionObserver(fireAllObserverCallbacks, {
      root,
      ...options
    });
  }
  return rootObservers[key];
}
function observeIntersection(element, options, callback) {
  const rootInteresectionObserver = initIntersectionObserver(options);
  observerCallbacks.set(element, callback);
  rootInteresectionObserver.observe(element);
  return () => {
    observerCallbacks.delete(element);
    rootInteresectionObserver.unobserve(element);
  };
}

// dist/features.js
var AnimationFeature = class extends Feature {
  unmountControls;
  constructor(node) {
    super(node);
    node.animationState ||= createAnimationState(node);
  }
  updateAnimationControlsSubscription() {
    const {
      animate
    } = this.node.getProps();
    if (isAnimationControls(animate)) {
      this.unmountControls = animate.subscribe(this.node);
    }
  }
  mount() {
    this.updateAnimationControlsSubscription();
  }
  update() {
    const {
      animate
    } = this.node.getProps();
    const {
      animate: prevAnimate
    } = this.node.prevProps || {};
    if (animate !== prevAnimate) {
      this.updateAnimationControlsSubscription();
    }
  }
  unmount() {
    this.node.animationState.reset();
    this.unmountControls?.();
  }
};
var exitId = 0;
var ExitAnimationFeature = class extends Feature {
  id = exitId++;
  isExitComplete = false;
  update() {
    if (!this.node.presenceContext) {
      return;
    }
    const {
      isPresent,
      onExitComplete
    } = this.node.presenceContext;
    const {
      isPresent: prevIsPresent
    } = this.node.prevPresenceContext || {};
    if (!this.node.animationState || isPresent === prevIsPresent) {
      return;
    }
    if (isPresent && prevIsPresent === false) {
      if (this.isExitComplete) {
        const {
          initial,
          custom
        } = this.node.getProps();
        if (typeof initial === "string" || typeof initial === "object" && initial !== null && !Array.isArray(initial)) {
          const resolved = resolveVariant(this.node, initial, custom);
          if (resolved) {
            const {
              transition: _transition,
              transitionEnd: _transitionEnd,
              ...target
            } = resolved;
            for (const key in target) {
              this.node.getValue(key)?.jump(target[key]);
            }
          }
        }
        this.node.animationState.reset();
        this.node.animationState.animateChanges();
      } else {
        this.node.animationState.setActive("exit", false);
      }
      this.isExitComplete = false;
      return;
    }
    const exitAnimation = this.node.animationState.setActive("exit", !isPresent);
    if (onExitComplete && !isPresent) {
      exitAnimation.then(() => {
        this.isExitComplete = true;
        onExitComplete(this.id);
      });
    }
  }
  mount() {
    const {
      register,
      onExitComplete
    } = this.node.presenceContext || {};
    if (onExitComplete) {
      onExitComplete(this.id);
    }
    if (register) {
      this.unmount = register(this.id);
    }
  }
  unmount() {
  }
};
var featureProps = {
  animation: ["animate", "variants", "whileHover", "whileTap", "exit", "whileInView", "whileFocus", "whileDrag"],
  exit: ["exit"],
  layout: ["layout", "layoutId"],
  drag: ["drag", "dragControls"],
  pan: ["onPan", "onPanStart", "onPanSessionStart", "onPanEnd"],
  focus: ["whileFocus"],
  hover: ["whileHover", "onHoverStart", "onHoverEnd"],
  tap: ["whileTap", "onTap", "onTapStart", "onTapCancel"],
  inView: ["whileInView", "onViewportEnter", "onViewportLeave"]
};
var isEnabled = (names) => (props) => names.some((n) => !!props[n]);
var initialized = false;
function initFeatures() {
  if (initialized) {
    return;
  }
  initialized = true;
  addScaleCorrector({
    borderRadius: {
      ...correctBorderRadius,
      applyTo: ["borderTopLeftRadius", "borderTopRightRadius", "borderBottomLeftRadius", "borderBottomRightRadius"]
    },
    borderTopLeftRadius: correctBorderRadius,
    borderTopRightRadius: correctBorderRadius,
    borderBottomLeftRadius: correctBorderRadius,
    borderBottomRightRadius: correctBorderRadius,
    boxShadow: correctBoxShadow
  });
  setFeatureDefinitions({
    animation: {
      isEnabled: isEnabled(featureProps["animation"]),
      Feature: AnimationFeature
    },
    exit: {
      isEnabled: isEnabled(featureProps["exit"]),
      Feature: ExitAnimationFeature
    },
    layout: {
      isEnabled: isEnabled(featureProps["layout"]),
      ProjectionNode: HTMLProjectionNode
    },
    // the drag and pan gestures are vendored from Motion (they are not exported by motion-dom)
    drag: {
      isEnabled: isEnabled(featureProps["drag"]),
      Feature: DragGesture,
      ProjectionNode: HTMLProjectionNode
    },
    pan: {
      isEnabled: isEnabled(featureProps["pan"]),
      Feature: PanGesture
    },
    // gestures (hover / press / focus / in-view): Motion's feature classes over the engine's hover() / press()
    hover: {
      isEnabled: isEnabled(featureProps["hover"]),
      Feature: HoverGesture
    },
    tap: {
      isEnabled: isEnabled(featureProps["tap"]),
      Feature: PressGesture
    },
    focus: {
      isEnabled: isEnabled(featureProps["focus"]),
      Feature: FocusGesture
    },
    inView: {
      isEnabled: isEnabled(featureProps["inView"]),
      Feature: InViewFeature
    }
  });
}

// dist/motion-config.js
import Component3 from "@glimmer/component";
import { modifier as modifier4 } from "ember-modifier";
import { precompileTemplate as precompileTemplate3 } from "@ember/template-compilation";
import { setComponentTemplate as setComponentTemplate3 } from "@ember/component";
var configs = /* @__PURE__ */ new WeakMap();
function closestMotionConfig(el) {
  const host = el.parentElement?.closest("[data-motion-config]");
  const component = host && configs.get(host);
  return component ? component.config : {};
}
var MotionConfig = class extends Component3 {
  host;
  register = modifier4((el) => {
    this.host = el;
    configs.set(el, this);
    return () => {
      configs.delete(el);
      this.host = void 0;
    };
  });
  /** inherits from the closest parent MotionConfig, then applies its own args (transition via resolveTransition) */
  get config() {
    const parent = this.host ? closestMotionConfig(this.host) : {};
    const own = {};
    for (const key of ["transition", "reducedMotion", "transformPagePoint", "skipAnimations", "nonce"]) {
      if (this.args[key] !== void 0) {
        own[key] = this.args[key];
      }
    }
    const config = {
      ...parent,
      ...own
    };
    config.transition = resolveTransition(config.transition, parent.transition);
    return config;
  }
  static {
    setComponentTemplate3(precompileTemplate3('\n    <div data-motion-config style="display: contents" {{this.register}} ...attributes>\n      {{yield}}\n    </div>\n  ', {
      strictMode: true
    }), this);
  }
};

// dist/unitless.js
var UNITLESS2 = /* @__PURE__ */ new Set([
  "animationIterationCount",
  "aspectRatio",
  "borderImageOutset",
  "borderImageSlice",
  "borderImageWidth",
  "boxFlex",
  "boxFlexGroup",
  "boxOrdinalGroup",
  "columnCount",
  "columns",
  "fillOpacity",
  "flex",
  "flexGrow",
  "flexNegative",
  "flexOrder",
  "flexPositive",
  "flexShrink",
  "floodOpacity",
  "fontWeight",
  "gridArea",
  "gridColumn",
  "gridColumnEnd",
  "gridColumnSpan",
  "gridColumnStart",
  "gridRow",
  "gridRowEnd",
  "gridRowSpan",
  "gridRowStart",
  "lineClamp",
  "lineHeight",
  "opacity",
  "order",
  "orphans",
  "scale",
  "stopOpacity",
  "strokeDasharray",
  "strokeDashoffset",
  "strokeMiterlimit",
  "strokeOpacity",
  "strokeWidth",
  "tabSize",
  "widows",
  "zIndex",
  "zoom",
  // vendor-prefixed spellings React also treats as unitless
  "MozAnimationIterationCount",
  "MozBoxFlex",
  "MozBoxFlexGroup",
  "MozLineClamp",
  "msAnimationIterationCount",
  "msFlex",
  "msFlexGrow",
  "msFlexNegative",
  "msFlexOrder",
  "msFlexPositive",
  "msFlexShrink",
  "msGridColumn",
  "msGridColumnSpan",
  "msGridRow",
  "msGridRowSpan",
  "msZoom",
  "WebkitAnimationIterationCount",
  "WebkitBoxFlex",
  "WebkitBoxFlexGroup",
  "WebkitBoxOrdinalGroup",
  "WebkitColumnCount",
  "WebkitColumns",
  "WebkitFlex",
  "WebkitFlexGrow",
  "WebkitFlexPositive",
  "WebkitFlexShrink",
  "WebkitLineClamp"
]);
var styleValue = (key, value) => typeof value === "number" && value !== 0 && !UNITLESS2.has(key) ? `${value}px` : String(value);

// dist/node.js
var DEFAULT_LAYOUT_TRANSITION = {
  duration: 0.45,
  ease: [0.4, 0, 0.1, 1]
};
var treeVariants = /* @__PURE__ */ new WeakMap();
var presenceOf = /* @__PURE__ */ new WeakMap();
var nodeOf = /* @__PURE__ */ new WeakMap();
var sameTree = (a, b) => a?.initial === b?.initial && a?.animate === b?.animate;
function currentTreeVariants(props, context) {
  if (isControllingVariants(props)) {
    const {
      initial,
      animate
    } = props;
    return {
      initial: initial === false || isVariantLabel(initial) ? initial : void 0,
      animate: isVariantLabel(animate) ? animate : void 0
    };
  }
  return props.inherit !== false ? context : {};
}
function makeLatestValues(props, parent, blockInitial, svg = false) {
  const values = {};
  const motionValues = (svg ? scrapeMotionValuesFromProps2 : scrapeMotionValuesFromProps)(props, {}, void 0);
  for (const key in motionValues) {
    values[key] = resolveMotionValue(motionValues[key]);
  }
  let {
    initial,
    animate
  } = props;
  const controlling = isControllingVariants(props);
  const variantNode = isVariantNode(props);
  const context = (parent && treeVariants.get(parent)) ?? {};
  if (parent && variantNode && !controlling && props.inherit !== false) {
    if (initial === void 0) {
      initial = context.initial;
    }
    if (animate === void 0) {
      animate = context.animate;
    }
  }
  const blocked = blockInitial || initial === false;
  const variantToSet = blocked ? animate : initial;
  if (variantToSet && typeof variantToSet !== "boolean" && !isAnimationControls(variantToSet)) {
    const list = Array.isArray(variantToSet) ? variantToSet : [variantToSet];
    for (const v of list) {
      const resolved = resolveVariantFromProps(props, v);
      if (!resolved) {
        continue;
      }
      const {
        transitionEnd,
        transition: _transition,
        ...target
      } = resolved;
      for (const key in target) {
        let t = target[key];
        if (Array.isArray(t)) {
          t = t[blocked ? t.length - 1 : 0];
        }
        if (t !== null) {
          values[key] = t;
        }
      }
      for (const key in transitionEnd) {
        values[key] = transitionEnd[key];
      }
    }
  }
  return values;
}
var CLAIMED = "data-gm-touch-action";
function touchAction(element, drag) {
  if (!drag) {
    if (element.hasAttribute(CLAIMED)) {
      element.removeAttribute(CLAIMED);
      element.style.touchAction = "";
    }
    return;
  }
  const axis = drag === true ? "none" : drag === "x" ? "pan-y" : "pan-x";
  if (element.style.touchAction !== axis) {
    element.style.touchAction = axis;
  }
  if (!element.hasAttribute(CLAIMED)) {
    element.setAttribute(CLAIMED, "");
  }
}
function closestVisualElement(el) {
  let p = el.parentElement;
  while (p) {
    const ve = visualElementStore.get(p);
    if (ve) {
      return ve;
    }
    p = p.parentElement;
  }
  return void 0;
}
function closestProjection(ve) {
  if (!ve) {
    return void 0;
  }
  return ve.options.allowProjection !== false ? ve.projection : closestProjection(ve.parent);
}
var pendingPops = [];
var popFlushBooked = false;
function seatOf(el) {
  const parent = el.offsetParent;
  const cs = getComputedStyle(el);
  const w = parseFloat(cs.width), h = parseFloat(cs.height);
  if (!w || !h) {
    return void 0;
  }
  return {
    h,
    isRTL: cs.direction === "rtl",
    left: el.offsetLeft,
    parentHeight: parent?.offsetHeight ?? 0,
    parentWidth: parent?.offsetWidth ?? 0,
    top: el.offsetTop,
    w
  };
}
function flushPendingPops() {
  if (!pendingPops.length) {
    return;
  }
  popFlushBooked = false;
  for (const {
    apply: apply2
  } of pendingPops.splice(0)) {
    apply2();
  }
}
var pendingMounts = /* @__PURE__ */ new Set();
function flushPendingMounts() {
  flushPendingPops();
  if (!pendingMounts.size) {
    return;
  }
  const list = [...pendingMounts].sort((a, b) => a.element.compareDocumentPosition(b.element) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1);
  pendingMounts.clear();
  for (const m of list) {
    m.create();
  }
  const stack = [];
  for (const m of list) {
    while (stack.length && !stack[stack.length - 1].element.contains(m.element)) {
      stack.pop().mountNow();
    }
    stack.push(m);
  }
  while (stack.length) {
    stack.pop().mountNow();
  }
}
setMountFlusher(flushPendingMounts);
registerBusyProbe(() => pendingMounts.size ? `${pendingMounts.size} motion element(s) waiting to mount` : pendingPops.length ? `${pendingPops.length} popLayout leaver(s) waiting to be lifted` : false);
function describe(el) {
  if (!el) {
    return "<detached>";
  }
  const cls = typeof el.className === "string" ? el.className.trim() : "";
  return `${el.tagName.toLowerCase()}${el.id ? `#${el.id}` : ""}${cls ? `.${cls.split(/\s+/).join(".")}` : ""}`;
}
var layoutPresenceId = 0;
var MotionNode = class {
  ve;
  destroyed = false;
  /** this node's registration with its presence child (MeasureLayout registers per node) */
  layoutPresenceKey = `layout:${layoutPresenceId++}`;
  element;
  latest;
  lastPresent;
  config = {};
  /** React: configAndProps = { ...MotionConfigContext, ...props }. Looked up when used, not when the args
   *  arrive: modifiers install children-first, so a <MotionConfig> above has not registered yet at update time */
  configured(props) {
    const config = this.config = this.element ? closestMotionConfig(this.element) : {};
    const defaults = {};
    if (config.transition !== void 0) {
      defaults["transition"] = config.transition;
    }
    if (config.transformPagePoint) {
      defaults["transformPagePoint"] = config.transformPagePoint;
    }
    const merged = {
      ...defaults,
      ...props
    };
    let source = merged.transition;
    if (source === void 0 && motionSpeed() !== 1 && (merged.layout !== void 0 || merged.layoutId !== void 0)) {
      source = DEFAULT_LAYOUT_TRANSITION;
    }
    const scaled = slowed(source);
    return scaled === merged.transition ? merged : {
      ...merged,
      transition: scaled
    };
  }
  /** re-configure when the global speed changes, so the next layout animation is born slowed */
  watchSpeed() {
    this.unsubscribeSpeed ??= onMotionSpeed(() => {
      if (this.ve && !this.destroyed && this.element && this.latest) {
        this.apply(this.element, this.configured(this.latest.props), this.latest.ownPresence);
      }
    });
  }
  unsubscribeSpeed;
  stopProbe;
  unregister;
  popStyle;
  /** the seat measured before the render that removed this element */
  popSeat;
  unregisterPop;
  /** boxel-motion's sprite identity: a <Choreo> above selects this element by these */
  id = null;
  role = null;
  choreo;
  presenceRegistered = false;
  constructor() {
    initFeatures();
  }
  /** React render: the element's props for this pass */
  update(element, named) {
    const {
      presence: ownPresence,
      id: id2,
      role,
      pack,
      ...rest
    } = named;
    this.id = id2 ?? null;
    this.role = role ?? null;
    if (pack === "content") {
      element.setAttribute("data-choreo-pack", "content");
    } else {
      element.removeAttribute("data-choreo-pack");
    }
    const props = {
      ...rest
    };
    if (named.dragConstraints instanceof Element) {
      props.dragConstraints = {
        current: named.dragConstraints
      };
    }
    this.element = element;
    touchAction(element, props.drag);
    this.latest = {
      props,
      ownPresence
    };
    void ownPresence?.isPresent;
    if (!this.ve) {
      if (!pendingMounts.size) {
        postRender(flushPendingMounts);
      }
      pendingMounts.add(this);
      return;
    }
    this.apply(element, this.configured(props), ownPresence);
  }
  unsubscribePresence;
  /** React render: construct the VisualElement (not yet mounted) */
  create() {
    if (this.ve || this.destroyed || !this.element || !this.latest) {
      return;
    }
    const element = this.element;
    const {
      ownPresence
    } = this.latest;
    const props = this.configured(this.latest.props);
    const parent = closestVisualElement(element);
    const presence = ownPresence ?? (parent ? presenceOf.get(parent) : void 0);
    const presenceContext = presence ? presence.context : null;
    {
      const blockInitial = presenceContext?.initial === false;
      const svg = isSVGElement(element);
      const Ctor = svg ? SVGVisualElement : HTMLVisualElement;
      const renderState = svg ? {
        style: {},
        transform: {},
        transformOrigin: {},
        vars: {},
        attrs: {}
      } : {
        style: {},
        transform: {},
        transformOrigin: {},
        vars: {}
      };
      const ve = new Ctor({
        visualState: {
          latestValues: makeLatestValues(props, parent, blockInitial, svg),
          renderState
        },
        parent,
        presenceContext,
        props,
        blockInitialAnimation: blockInitial,
        // React's MotionConfigContext defaults this to "never" — Motion is a
        // library you opt into, so it assumes you meant it. On the web
        // platform the person's setting is the default and honouring it is
        // not a feature: `prefers-reduced-motion: reduce` disables transform
        // and layout animation here unless a <MotionConfig> above says
        // otherwise. Porting a React app that relied on the other default is
        // one attribute: <MotionConfig @reducedMotion="never">.
        reducedMotionConfig: this.config.reducedMotion ?? "user",
        skipAnimations: this.config.skipAnimations
      }, {
        allowProjection: true
      });
      this.ve = ve;
      this.stopProbe = registerBusyProbe(() => {
        const live = this.ve;
        if (!live || this.destroyed) {
          return false;
        }
        for (const [key, value] of live.values) {
          if (value.isAnimating() && value.animation?.state !== "paused") {
            return `${describe(this.element)} ${key}`;
          }
        }
        if (live.projection?.currentAnimation) {
          return `${describe(this.element)} layout`;
        }
        return false;
      });
      nodeOf.set(ve, this);
      visualElementStore.set(element, ve);
      treeVariants.set(ve, currentTreeVariants(props, (parent && treeVariants.get(parent)) ?? {}));
      if (presence) {
        presenceOf.set(ve, presence);
        this.unsubscribePresence = presence.subscribe(() => this.refresh());
      }
      if (ownPresence) {
        this.unregisterPop = ownPresence.popCandidate(this);
      }
      if (props.layout || props.layoutId || props.drag) {
        const portalled = element.hasAttribute("data-framer-portal-id");
        const projection = new HTMLProjectionNode(ve.latestValues, portalled ? void 0 : closestProjection(parent));
        ve.projection = projection;
        const group = closestLayoutGroup(element);
        const layoutId = group?.id && props.layoutId !== void 0 ? `${group.id}-${props.layoutId}` : props.layoutId;
        if (group?.group) {
          group.group.add(projection);
          const remove = () => group.group.remove(projection);
          const prev = this.unregister;
          this.unregister = () => {
            prev?.();
            remove();
          };
        }
        projection.setOptions({
          layoutId,
          layout: props.layout,
          visualElement: ve,
          animationType: typeof props.layout === "string" ? props.layout : "both",
          // createProjectionNode: draggables (and ref-constrained ones) always measure
          alwaysMeasureLayout: Boolean(props.drag) || Boolean(props.dragConstraints && typeof props.dragConstraints === "object" && "current" in props.dragConstraints),
          crossfade: props.layoutCrossfade,
          layoutScroll: props.layoutScroll,
          layoutRoot: props.layoutRoot,
          layoutAnchor: props.layoutAnchor,
          layoutDependency: props.layoutDependency,
          onExitComplete: () => presenceContext?.onExitComplete?.(this.layoutPresenceKey)
        });
        if (presenceContext?.register) {
          const release = presenceContext.register(this.layoutPresenceKey);
          this.presenceRegistered = true;
          const beforeRelease = this.unregister;
          this.unregister = () => {
            beforeRelease?.();
            release?.();
          };
        }
        const unregisterProjection = registerProjection(projection);
        const prevUnregister = this.unregister;
        this.unregister = () => {
          prevUnregister?.();
          unregisterProjection();
        };
      }
    }
  }
  /** React effect: mount → update → features → animateChanges */
  mountNow() {
    const ve = this.ve;
    if (!ve || ve.current || this.destroyed || !this.element || !this.latest) {
      return;
    }
    const element = this.element;
    const {
      ownPresence
    } = this.latest;
    const props = this.configured(this.latest.props);
    const presence = ownPresence ?? presenceOf.get(ve);
    const isPresent = presence ? presence.isPresent : true;
    const presenceContext = presence ? presence.context : null;
    {
      this.applyStyle(element, props, void 0);
      ve.mount(element);
      ve.render();
      const mountContext = presenceContext && !isPresent ? {
        ...presenceContext,
        isPresent: true
      } : presenceContext;
      ve.update(props, mountContext);
      ve.updateFeatures();
      ve.scheduleRenderMicrotask();
      if (this.id !== null || this.role !== null) {
        this.joinChoreo(element, presenceContext);
      }
      if (ve.projection) {
        this.watchSpeed();
        if (hasTakenAnySnapshot) {
          requestSettle();
        }
        ve.projection.addEventListener("animationComplete", () => presenceContext?.onExitComplete?.(this.layoutPresenceKey));
      }
      ve.animationState?.animateChanges();
      ve.enteringChildren = void 0;
      if (mountContext !== presenceContext) {
        this.lastPresent = true;
        this.apply(element, props, ownPresence);
        return;
      }
      this.lastPresent = isPresent;
    }
  }
  /** every later pass: React's update → updateFeatures → animateChanges */
  apply(element, props, ownPresence) {
    const ve = this.ve;
    const parent = ve.parent;
    const presence = ownPresence ?? (parent ? presenceOf.get(parent) : void 0);
    const isPresent = presence ? presence.isPresent : true;
    if (!isPresent && ve.current) {
      props = ve.getProps();
    }
    const presenceContext = presence ? presence.context : null;
    const nextTree = currentTreeVariants(props, (parent && treeVariants.get(parent)) ?? {});
    const treeChanged = !sameTree(treeVariants.get(ve), nextTree);
    treeVariants.set(ve, nextTree);
    const projection = ve.projection;
    if (projection) {
      const prevDep = ve.getProps().layoutDependency;
      const nextDep = props.layoutDependency;
      if (nextDep !== void 0 && prevDep === nextDep && this.lastPresent === isPresent) {
        projection.clearSnapshot();
      }
      projection.setOptions({
        ...projection.options,
        layoutDependency: nextDep,
        layoutAnchor: props.layoutAnchor
      });
    }
    const pops = ownPresence?.mode === "popLayout";
    const presenceFlipped = this.lastPresent !== isPresent;
    if (projection && this.lastPresent !== isPresent) {
      projection.isPresent = isPresent;
      if (pops) {
        this.pop(element, isPresent, ownPresence);
      }
      if (isPresent) {
        projection.promote();
      } else if (!projection.relegate()) {
        frame.postRender(() => {
          const stack = projection.getStack();
          const others = stack?.members.filter((m) => m !== projection) ?? [];
          if (!others.length) {
            presenceContext?.onExitComplete?.(this.layoutPresenceKey);
          }
        });
      }
    } else if (!projection && pops && this.lastPresent !== isPresent) {
      this.pop(element, isPresent, ownPresence);
    }
    this.applyStyle(element, props, ve.getProps());
    ve.update(props, presenceContext);
    ve.updateFeatures();
    ve.scheduleRenderMicrotask();
    ve.animationState?.animateChanges();
    if (projection) {
      afterSettle(() => {
        if (!projection.currentAnimation && projection.isLead()) {
          presenceContext?.onExitComplete?.(this.layoutPresenceKey);
        }
      });
    }
    this.lastPresent = isPresent;
    if (treeChanged || presenceFlipped) {
      ve.children.forEach((child) => nodeOf.get(child)?.refresh());
    }
  }
  /* ---- ChoreoNode: what a <Choreo> above needs from this element ---- */
  /** a participant registers with the nearest region, and with its Presence so a timeline can outlive a plain exit */
  joinChoreo(element, presenceContext) {
    const host = closestChoreo(element);
    if (!host) {
      return;
    }
    this.choreo = host;
    const leave2 = host.register(this);
    if (presenceContext?.register && !this.presenceRegistered) {
      const release = presenceContext.register(this.layoutPresenceKey);
      this.presenceRegistered = true;
      const before2 = this.unregister;
      this.unregister = () => {
        before2?.();
        release?.();
      };
    }
    const before = this.unregister;
    this.unregister = () => {
      before?.();
      leave2();
    };
  }
  get visualElement() {
    return this.ve;
  }
  get layoutKey() {
    return this.layoutPresenceKey;
  }
  /** for the region's @debug lints (§5.3) */
  get ownAnimation() {
    const props = this.latest?.props;
    return Boolean(props && (props.animate || props.exit || props.initial));
  }
  get presenceManaged() {
    return Boolean(this.latest?.ownPresence);
  }
  get isPresent() {
    const presence = this.latest?.ownPresence ?? (this.ve && presenceOf.get(this.ve));
    return presence ? presence.isPresent : true;
  }
  /** the choreography is done with a leaving element: tell its Presence */
  exitComplete() {
    const presence = this.latest?.ownPresence ?? (this.ve && presenceOf.get(this.ve));
    presence?.context.onExitComplete?.(this.layoutPresenceKey);
  }
  /** the choreography is done with an element whose unmount it deferred */
  release() {
    const ve = this.ve;
    if (!ve) {
      return;
    }
    this.ve = void 0;
    ve.unmount();
  }
  /** re-run the update pass with the latest args (a context or presence change above us) */
  refresh() {
    if (this.ve?.current && this.element && this.latest) {
      this.apply(this.element, this.configured(this.latest.props), this.latest.ownPresence);
    }
  }
  /** the non-motion-value part of `style` goes straight onto the element, as React's style attribute would —
   *  except keys the engine already owns (it renders those itself, and decides whether a style change applies) */
  applyStyle(el, props, prev) {
    const style2 = props.style;
    const prevStyle = prev?.style;
    if (style2 === prevStyle) {
      return;
    }
    if (prevStyle) {
      for (const key in prevStyle) {
        if (!style2 || !(key in style2)) {
          el.style.removeProperty(key.startsWith("--") ? key : key.replace(/[A-Z]/g, (m) => "-" + m.toLowerCase()));
        }
      }
    }
    if (!style2) {
      return;
    }
    for (const key in style2) {
      const v = style2[key];
      if (isMotionValue(v) || v === void 0 || v === null) {
        continue;
      }
      if (this.ve?.hasValue(key)) {
        continue;
      }
      if (key.startsWith("--")) {
        el.style.setProperty(key, String(v));
      } else if (key in el.style) {
        el.style[key] = styleValue(key, v);
      }
    }
  }
  /**
   * React's PopChildMeasure.getSnapshotBeforeUpdate: the seat this element
   * occupies, read BEFORE the render that removes it.
   *
   * <Presence> calls this from its own diff, while the arrivals for this pass
   * are still unrendered. Measuring later reads a layout that already holds
   * them — the container has grown, and a centred one has moved — so the
   * leaver would be pinned somewhere it never stood.
   */
  measureForPop() {
    const el = this.element;
    if (el?.isConnected) {
      this.popSeat = seatOf(el);
    }
  }
  /** popLayout: a leaving element is lifted out of flow at its last box so siblings can close up */
  pop(el, isPresent, handle) {
    if (isPresent) {
      this.popStyle?.remove();
      this.popStyle = void 0;
      this.popSeat = void 0;
      el.removeAttribute("data-motion-pop-id");
      return;
    }
    const seat = this.popSeat ?? seatOf(el);
    this.popSeat = void 0;
    if (!seat) {
      return;
    }
    const {
      w,
      h,
      top,
      left,
      parentWidth,
      parentHeight,
      isRTL
    } = seat;
    const right = parentWidth - w - left, bottom = parentHeight - h - top;
    const x = handle.anchorX === "left" ? isRTL ? `right:${right}` : `left:${left}` : isRTL ? `left:${left}` : `right:${right}`;
    const y = handle.anchorY === "bottom" ? `bottom:${bottom}` : `top:${top}`;
    const id2 = `pop-${Math.random().toString(36).slice(2, 8)}`;
    el.dataset["motionPopId"] = id2;
    pendingPops.push({
      apply: () => {
        if (this.destroyed || el.dataset["motionPopId"] !== id2) {
          return;
        }
        const style2 = document.createElement("style");
        if (this.config.nonce) {
          style2.nonce = this.config.nonce;
        }
        document.head.appendChild(style2);
        style2.sheet?.insertRule(`[data-motion-pop-id="${id2}"]{position:absolute!important;width:${w}px!important;height:${h}px!important;${x}px!important;${y}px!important;}`);
        this.popStyle = style2;
      }
    });
    if (!popFlushBooked) {
      popFlushBooked = true;
      queueMicrotask(flushPendingPops);
    }
  }
  /** React unmount */
  destroy() {
    this.destroyed = true;
    pendingMounts.delete(this);
    this.unsubscribePresence?.();
    this.unregisterPop?.();
    this.unsubscribeSpeed?.();
    this.stopProbe?.();
    this.stopProbe = void 0;
    const ve = this.ve;
    if (!ve) {
      return;
    }
    ve.projection?.scheduleCheckAfterUnmount?.();
    this.unregister?.();
    this.popStyle?.remove();
    if (this.choreo?.claim(this)) {
      return;
    }
    ve.unmount();
    this.ve = void 0;
  }
};

// dist/choreo.js
import { precompileTemplate as precompileTemplate4 } from "@ember/template-compilation";
import { setComponentTemplate as setComponentTemplate4 } from "@ember/component";
var selector = (type) => Object.assign((role) => role === void 0 ? {
  type
} : {
  role,
  type
}, {
  type
});
function contextFor(region) {
  return {
    Aim,
    Attach,
    Camera,
    Camera3D,
    Crossing,
    Follow,
    Frame,
    Gate,
    Hold,
    Move,
    Pan,
    Parallel,
    Perform,
    Raise,
    Scroll,
    Sequence,
    SlowZoom,
    Spring,
    Tether,
    Tween,
    Wait,
    advance: () => region.run?.advance(),
    all: selector(),
    beacon: (beacon2) => ({
      beacon: beacon2
    }),
    gesture: GESTURE,
    counterpart: selector("counterpart"),
    id: (id2) => ({
      id: id2
    }),
    inserted: selector("inserted"),
    kept: selector("kept"),
    moved: selector("moved"),
    onstage: (query) => ({
      ...query,
      onstage: true
    }),
    received: selector("received"),
    removed: selector("removed"),
    role: (role) => ({
      role
    }),
    get camera() {
      return region.cameraState;
    },
    get run() {
      return region.run ?? null;
    },
    still: selector("still")
  };
}
var debugStyle;
var orphanStyle;
function ensureOrphanStyle() {
  if (orphanStyle) {
    return;
  }
  orphanStyle = document.createElement("style");
  orphanStyle.setAttribute("data-choreo-style", "");
  orphanStyle.textContent = "[data-choreo-orphans] *,[data-choreo-orphans] *::before,[data-choreo-orphans] *::after{backdrop-filter:none!important;-webkit-backdrop-filter:none!important;animation:none!important;}";
  document.head.appendChild(orphanStyle);
}
var fnIds = /* @__PURE__ */ new WeakMap();
var nextFnId = 0;
function treePrint(tree) {
  return JSON.stringify(tree, (_key, value) => {
    if (typeof value === "function") {
      let id2 = fnIds.get(value);
      if (id2 === void 0) {
        fnIds.set(value, id2 = ++nextFnId);
      }
      return `fn#${id2}`;
    }
    return value;
  });
}
function groundOf(root) {
  let el = root;
  while (el) {
    const bg = getComputedStyle(el).backgroundColor;
    if (bg && bg !== "transparent" && !/rgba\([^)]*,\s*0\)$/.test(bg)) {
      return bg;
    }
    el = el.parentElement;
  }
  return void 0;
}
setPassScheduler((run) => postRender(run));
setBeforeMeasure(() => flushPendingMounts());
var Choreo = class extends Component4 {
  element;
  orphanLayer;
  raisedLayer;
  tetherLayer;
  static {
    decorateFieldV2(this.prototype, "cameraState", [tracked2], function() {
      return {
        x: 0,
        y: 0,
        zoom: 1
      };
    });
  }
  #cameraState = (initializeDeferredDecorator(this, "cameraState"), void 0);
  /**
  * The same state, untracked, for the pass pipeline itself. A pass runs
  * inside computations that must not CONSUME the tracked mirror — a pass
  * that read it would be invalidated by the very landing it causes, and
  * the region would render forever.
  */
  /** where a c.Camera3D left the shot, carried between runs — seeded by
  *  `@camera3dFrom` when the host knows its own opening pose */
  resting3d = this.args.camera3dFrom ? {
    ...this.args.camera3dFrom
  } : {
    dolly: 1,
    pitch: 0,
    x: 0,
    y: 0,
    yaw: 0
  };
  restingCamera = {
    x: 0,
    y: 0,
    zoom: 1
  };
  participants = /* @__PURE__ */ new Set();
  /** registered since the last pass */
  arrived = /* @__PURE__ */ new Set();
  /** destroyed before the pass that removed them has been processed */
  claimed = /* @__PURE__ */ new Set();
  /** removed participants this region is keeping alive in its orphan layer */
  orphans = /* @__PURE__ */ new Set();
  /** participants whose Presence is letting them go: removed once, not on every pass while they leave */
  leaving = /* @__PURE__ */ new Set();
  snapshots = /* @__PURE__ */ new Map();
  rootSnapshot;
  passPending = false;
  rendered = false;
  run;
  context = contextFor(this);
  /** the last changeset this region built — read it from a property function or a test */
  changeset;
  constructor(owner, args) {
    super(owner, args);
    trackGestures();
    const stopProbe = registerBusyProbe(() => {
      if (this.passPending) {
        return `<Choreo${this.args.id ? ` ${this.args.id}` : ""}> pass pending`;
      }
      if (this.run && !this.run.isDone() && !this.run.parked && !this.run.standing) {
        return `<Choreo${this.args.id ? ` ${this.args.id}` : ""}> run in flight`;
      }
      return false;
    });
    registerDestructor(this, () => {
      stopProbe();
      leave(this);
      this.run?.cancel();
      this.run = void 0;
      this.unquiet();
      for (const node of [...this.orphans, ...this.claimed]) {
        this.drop(node);
      }
    });
  }
  /* ---- ChoreoHost ---- */
  /** SPIKE (Lane): providers from outside the markup, appended to every collected tree */
  contributors = /* @__PURE__ */ new Set();
  contribute(provider) {
    this.contributors.add(provider);
    return () => {
      this.contributors.delete(provider);
    };
  }
  /** the run an attachment drives: the one playing or holding, none between runs */
  currentRun() {
    return this.run ?? null;
  }
  /** the region's own steps in document order, then whatever was contributed from outside */
  collectTree(root) {
    const tree = collect(root);
    for (const provider of this.contributors) {
      tree.push(provider.node());
    }
    return tree;
  }
  register(node) {
    this.participants.add(node);
    this.arrived.add(node);
    if (this.args.debug && node.element) {
      node.element.style.outline = "1px dotted #16a34a";
      if (node.ownAnimation) {
        console.warn(`choreo: participant '${node.id ?? node.role}' carries its own animate/exit/initial \u2014 a second scheduler beside the timeline`);
      }
      if (node.presenceManaged) {
        console.warn(`choreo: participant '${node.id ?? node.role}' is inside a <Presence> \u2014 the region already retains its own leavers`);
      }
    }
    return () => {
      this.participants.delete(node);
      this.arrived.delete(node);
    };
  }
  claim(node) {
    if (this.orphans.has(node)) {
      return true;
    }
    if (this.passPending) {
      this.claimed.add(node);
      return true;
    }
    return false;
  }
  /* ---- the render pass ---- */
  /* note (ember/no-side-effects): this getter IS the render hook: boxel-motion's render detector,
  re-evaluated on every render pass before the DOM is patched (React's getSnapshotBeforeUpdate slot) */
  get renderDetector() {
    consumeTag2(VOLATILE_TAG2);
    snapshotOnRender();
    if (!this.passPending) {
      this.passPending = true;
      this.snapshot();
      join(this);
    }
    return void 0;
  }
  /* end note */
  snapshot() {
    this.snapshots.clear();
    this.rootSnapshot = this.element?.getBoundingClientRect();
    for (const node of this.participants) {
      const el = node.element;
      if (el?.isConnected && !this.orphans.has(node)) {
        this.snapshots.set(node, measure(el));
      }
    }
  }
  /** phase 1: what changed this pass, measured — nothing is played yet */
  measurePass() {
    this.passPending = false;
    const root = this.element;
    if (!root) {
      return void 0;
    }
    if (this.fastKeep(root)) {
      return void 0;
    }
    this.run?.releaseForMeasure();
    if (this.args.route && this.arrived.size && this.snapshots.size) {
      const intent = this.args.scroll ?? "top";
      const y = intent === "top" ? 0 : intent();
      window.scrollTo(0, y);
    }
    const before = this.rootSnapshot ?? root.getBoundingClientRect();
    const after2 = root.getBoundingClientRect();
    const inserted = [];
    const removed = [];
    const kept = [];
    const sprite = (node, type, initial, final) => ({
      delta: initial && final ? {
        height: final.page.height - initial.page.height,
        width: final.page.width - initial.page.width,
        x: final.page.x - initial.page.x,
        y: final.page.y - initial.page.y
      } : void 0,
      element: node.element,
      final,
      id: node.id,
      initial,
      node,
      role: node.role,
      type
    });
    const candidates = /* @__PURE__ */ new Set([...this.participants, ...this.claimed, ...this.orphans]);
    for (const node of candidates) {
      const el = node.element;
      if (!el) {
        continue;
      }
      const snap = this.snapshots.get(node);
      if (this.orphans.has(node)) {
        const prior = this.orphanBounds.get(node);
        removed.push(sprite(node, "removed", prior));
      } else if (this.arrived.has(node)) {
        inserted.push(sprite(node, "inserted", void 0, boundsOf(measure(el), after2)));
      } else if (!el.isConnected || this.claimed.has(node)) {
        if (this.leaving.has(node)) {
          this.leaving.delete(node);
          this.drop(node);
        } else if (snap) {
          removed.push(sprite(node, "removed", boundsOf(snap, before)));
        } else if (this.claimed.has(node)) {
          this.drop(node);
        }
      } else if (!node.isPresent) {
        if (!this.leaving.has(node) && snap) {
          this.leaving.add(node);
          removed.push(sprite(node, "removed", boundsOf(snap, before)));
        }
      } else if (snap) {
        this.leaving.delete(node);
        kept.push(sprite(node, "kept", boundsOf(snap, before), boundsOf(measure(el), after2)));
      }
    }
    for (const s of inserted) {
      if (s.id === null) {
        continue;
      }
      const old = removed.find((r) => r.id === s.id && !r.counterpart);
      if (old) {
        old.claimed = true;
        s.counterpart = old;
        s.initial = old.initial;
        s.type = "kept";
        s.delta = s.initial && s.final && {
          height: s.final.page.height - s.initial.page.height,
          width: s.final.page.width - s.initial.page.width,
          x: s.final.page.x - s.initial.page.x,
          y: s.final.page.y - s.initial.page.y
        };
      }
    }
    this.arrived.clear();
    this.snapshots.clear();
    const claimed = [...this.claimed];
    this.claimed.clear();
    return {
      claimed,
      host: this,
      inserted,
      kept,
      removed,
      root
    };
  }
  /** phase 3: identities are settled — compile this region's timeline and play it */
  finishPass(pass) {
    const {
      claimed,
      inserted,
      kept,
      root
    } = pass;
    const removed = pass.removed.filter((s) => !s.sent);
    for (const s of pass.removed) {
      if (s.sent) {
        this.finish(s);
      }
    }
    const after2 = root.getBoundingClientRect();
    const layoutWidth = root.offsetWidth;
    const shadow = this.run?.camera.zoom ?? this.restingCamera.zoom;
    const painted = layoutWidth > 0 ? after2.width / layoutWidth : 0;
    const measureZoom = !painted || Math.abs(painted - shadow) < 4e-3 ? shadow : painted;
    const changeset = new Changeset(
      inserted.filter((s) => s.type === "inserted"),
      removed,
      [...kept, ...inserted.filter((s) => s.type === "kept")],
      // measured in the same window as `final`, and re-measured every pass: a
      // beacon can move without this region rendering at all
      measureBeacons(after2),
      measureZoom,
      // the frame's own size in the same final layout, local pixels — the
      // camera's centre reference, so aim terms are internally consistent
      {
        height: after2.height / measureZoom,
        width: after2.width / measureZoom
      },
      groundOf(root)
    );
    this.changeset = changeset;
    const firstRender = !this.rendered;
    this.rendered = true;
    if (this.args.route && motionSpeed() === 0) {
      for (const node of claimed) {
        this.drop(node);
      }
      for (const s of removed) {
        this.finish(s);
      }
      return;
    }
    const tree = firstRender ? [] : this.collectTree(root);
    const compiled = tree.length ? compile(tree, changeset) : {
      cues: [],
      gates: []
    };
    const cues2 = compiled.cues;
    if (this.run && !this.run.isDone()) {
      const scored = new Set(cues2.map((c) => c.sprite.node));
      for (const [node, transition] of this.run.midflight()) {
        if (scored.has(node)) {
          continue;
        }
        const s = changeset.kept.find((k) => k.node === node);
        if (!s) {
          continue;
        }
        const cue = continuation(s, changeset, transition);
        if (cue) {
          cues2.push(cue);
        }
      }
    }
    if (!cues2.length) {
      for (const node of claimed) {
        this.drop(node);
      }
      for (const s of removed) {
        if (s.node.presenceManaged && !s.node.isPresent && s.element.isConnected && !this.orphans.has(s.node)) {
          this.leaving.delete(s.node);
          continue;
        }
        this.finish(s);
      }
      return;
    }
    const print = treePrint(tree);
    const nothingNew = !inserted.length && pass.removed.every((s) => this.orphans.has(s.node)) && // A sprite mid-flight reads as "moved" on every re-pass — its initial
    // is the painted box, by design — so while this run's own orphans are
    // aloft, kept-motion cannot justify a recompile either: the score it
    // would produce is the degraded one above.
    (this.orphans.size > 0 || !changeset.sprites({
      type: "moved"
    }).length) && // …but an EDITED timeline is never noise: a changed tree replays,
    // exactly as it would with no orphans aloft (the build-order
    // transport's delay nudge, made while a leaver is frozen mid-park)
    print === this.scorePrint;
    if (this.run && !this.run.isDone() && nothingNew) {
      for (const node of claimed) {
        this.drop(node);
      }
      this.run.reassert();
      return;
    }
    if (this.run && !this.run.isDone() && !inserted.length && !pass.removed.length && !compiled.gates.length && print === this.scorePrint && sameScore(this.run.cues, cues2)) {
      for (const node of claimed) {
        this.drop(node);
      }
      this.run.reassert();
      return;
    }
    const named = new Set(cues2.map((c) => c.sprite));
    for (const s of [...kept, ...inserted]) {
      if (s.counterpart && named.has(s)) {
        named.add(s.counterpart);
      }
    }
    const prior = this.run;
    const inherited = prior !== void 0 && !prior.isDone() ? print === this.scorePrint ? {
      aim: prior.initialAim,
      camera: prior.initialCamera
    } : {
      aim: prior.cameraAim,
      camera: prior.camera
    } : {
      aim: prior?.cameraAim ?? null,
      camera: this.restingCamera
    };
    const shot3d = prior !== void 0 && !prior.isDone() ? prior.camera3d : this.resting3d;
    prior?.cancel(new Set([...named].map((s) => s.node)));
    for (const s of removed) {
      if (!named.has(s)) {
        this.finish(s);
      } else if (!s.element.isConnected || claimed.includes(s.node)) {
        this.orphan(s, removed, s.claimed === true);
      }
    }
    if (this.args.debug) {
      for (const s of removed) {
        if (!named.has(s)) {
          console.warn(`choreo: removed participant '${s.id ?? s.role}' is named by no step \u2014 it vanishes without a frame`);
        }
      }
      this.log(changeset, cues2);
    }
    this.scorePrint = print;
    this.layoutPrint = this.layoutOf();
    if (this.args.quiet) {
      this.quiet();
    }
    this.run = execute(compiled, {
      camera: {
        ...inherited.camera
      },
      camera3d: {
        ...shot3d
      },
      cameraFrame: this.element,
      // the aim point in force carries run to run, so a re-aim lerps from
      // what is actually applied rather than assuming an unaimed frame —
      // except a same-score re-execution, which carries the fold origin
      cameraAim: inherited.aim,
      // updated at step boundaries only — a still value app logic can
      // read. Guarded by equality: the landing itself renders, the render
      // is an all-kept pass, and the pass replays the camera step — an
      // unguarded set would revalidate forever.
      onCamera3D: (state) => {
        this.resting3d = state;
        this.args.onCamera3D?.(state);
      },
      onCamera: (state) => {
        const prior2 = this.restingCamera;
        this.restingCamera = state;
        if (prior2.zoom !== state.zoom || prior2.x !== state.x || prior2.y !== state.y) {
          postRender(() => this.cameraState = state);
        }
      },
      raisedLayer: this.raisedLayer,
      tetherLayer: this.tetherLayer,
      // ember-animated's continuity, in the terms motion-dom offers: it sums a
      // corrective curve onto the one it interrupted, which transfers velocity
      // implicitly; a spring takes a velocity outright, so the run that is
      // being replaced hands over how fast everything was going.
      inherit: prior?.velocities,
      onPerform: this.args.onPerform,
      onPerformReset: this.args.onPerformReset,
      onSpriteDone: (s) => this.finish(s),
      releaseOnSeek: this.args.releaseOnSeek,
      removed: removed.filter((s) => named.has(s)),
      // nothing in this region is staying: no participant kept, none
      // arriving, and every one it can see on its way out. A region in that
      // state is not watching a departure, it is inside one — see `park`.
      doomed: !kept.length && !inserted.length && removed.length > 0
    });
    if (this.args.quiet) {
      const run = this.run;
      void run.finished.then(() => {
        if (this.run === run) {
          this.unquiet();
        }
      });
    }
  }
  /* ---- orphans: a removed participant kept alive, locked where it was ---- */
  orphanBounds = /* @__PURE__ */ new Map();
  /** the fingerprint of the tree the current run compiled from (see treePrint) */
  scorePrint;
  /** the layout every participant stood in when the run compiled (see layoutPrint) */
  layoutPrint;
  /**
  * Where the stylesheet puts each participant, as a string.
  *
  * `offsetLeft/Top/Width/Height` and NOT a bounding rect, because the
  * difference is the whole point: a rect includes the transform a flight
  * is writing, so a moving element reads as different on every frame,
  * while offsets are the box layout asked for — steady under a transform,
  * and different the moment something actually reflows. Integers, too,
  * which quietly forgives the sub-pixel noise a busy page generates.
  *
  * A Move that animates real width/height (`@size={{true}}`) does change
  * these, so such a run never takes the fast path. That is the honest
  * answer rather than a missed optimisation: a run writing layout cannot
  * be told apart from a page writing layout without measuring.
  *
  * Offsets are accumulated up the offset chain to the region, not read
  * at the participant alone, because what a render moves may be an
  * ANCESTOR that is no participant of anything — Escort's seat, one
  * positioned wrapper carrying three participants. Read flat, the
  * fingerprint was blind to exactly the reflow a retarget makes, the
  * pass was declined, and the old run played on against the moved
  * layout: card, badge and shadow teleported a whole bay, together. The
  * walk stops at the region's edge so the page above it stays out of the
  * print — a busy neighbour reflowing above the region must not cancel
  * its runs.
  */
  layoutOf() {
    const root = this.element;
    const parts = [];
    for (const node of this.participants) {
      const el = node.element;
      if (!el || !el.isConnected) {
        continue;
      }
      let x = 0;
      let y = 0;
      let walk = el;
      while (walk && walk !== root && root?.contains(walk)) {
        x += walk.offsetLeft;
        y += walk.offsetTop;
        const parent = walk.offsetParent;
        walk = parent instanceof HTMLElement ? parent : null;
      }
      parts.push(`${node.id ?? node.role ?? ""}@${x},${y},${el.offsetWidth},${el.offsetHeight}`);
    }
    return parts.join("|");
  }
  /**
  * Can this pass be declined outright? Only while a run is in flight, and
  * only when nothing the pass could discover would change it: no arrivals,
  * no retentions pending, every participant either present or already a
  * known leaver, the collected timeline tree fingerprints identical to the
  * one the run compiled from (an EDIT always replays), and every
  * participant standing in the same layout box it compiled in (a REFLOW
  * always replays — it is what a Move is FOR). Anything else takes the
  * full pipeline.
  */
  fastKeep(root) {
    if (!this.run || this.run.isDone() || this.claimed.size || this.arrived.size) {
      return false;
    }
    if (this.run.paused) {
      return false;
    }
    for (const node of this.participants) {
      const el = node.element;
      if (!el || !el.isConnected) {
        return false;
      }
      if (!node.isPresent && !this.leaving.has(node) && !this.orphans.has(node)) {
        return false;
      }
    }
    return treePrint(this.collectTree(root)) === this.scorePrint && this.layoutOf() === this.layoutPrint;
  }
  /* ---- @quiet: the rest of the page, paused for the span of a run ---- */
  /** what quiet() paused, accumulated across replaced runs, resumed as one */
  quieted = [];
  quiet() {
    for (const animation of document.getAnimations()) {
      if (animation.playState === "running") {
        animation.pause();
        this.quieted.push(animation);
      }
    }
  }
  unquiet() {
    for (const animation of this.quieted.splice(0)) {
      try {
        animation.play();
      } catch {
      }
    }
  }
  orphan(s, removed, extract = false) {
    const inside = removed.some((o) => o !== s && o.element !== s.element && o.element.contains(s.element));
    if (inside && !extract || !s.initial) {
      return;
    }
    const layer = this.orphanLayer;
    const root = this.element;
    if (!layer || !root) {
      return;
    }
    const now2 = root.getBoundingClientRect();
    const sx = root.offsetWidth ? now2.width / root.offsetWidth : 1;
    const sy = root.offsetHeight ? now2.height / root.offsetHeight : 1;
    if (inside) {
      const seat = document.createElement("div");
      seat.style.width = `${s.initial.page.width / sx}px`;
      seat.style.height = `${s.initial.page.height / sy}px`;
      s.element.parentElement?.insertBefore(seat, s.element);
    }
    const {
      page
    } = s.initial;
    const el = s.element;
    el.style.position = "absolute";
    el.style.left = `${(page.x - now2.left) / sx}px`;
    el.style.top = `${(page.y - now2.top) / sy}px`;
    el.style.width = `${page.width / sx}px`;
    el.style.height = `${page.height / sy}px`;
    el.style.boxSizing = "border-box";
    el.style.margin = "0";
    el.style.pointerEvents = "none";
    el.style.willChange = "transform, opacity";
    layer.appendChild(el);
    this.orphans.add(s.node);
    this.orphanBounds.set(s.node, s.initial);
  }
  /** a removed sprite's row has ended */
  finish(s) {
    if (this.orphans.has(s.node) || this.participants.has(s.node)) {
      if (!s.element.isConnected || this.orphans.has(s.node)) {
        this.drop(s.node);
      } else if (!s.node.isPresent) {
        s.node.exitComplete();
      }
    } else {
      this.drop(s.node);
    }
  }
  drop(node) {
    const el = node.element;
    if (el && this.orphans.has(node) && el.parentElement === this.orphanLayer) {
      el.remove();
    }
    this.orphans.delete(node);
    this.orphanBounds.delete(node);
    this.claimed.delete(node);
    this.leaving.delete(node);
    this.participants.delete(node);
    node.release();
  }
  /* ---- debug ---- */
  log(changeset, cues2) {
    const id2 = this.args.id ?? "";
    const row2 = (s) => ({
      choreo: id2,
      final: s.final ? JSON.stringify(s.final.context) : null,
      id: s.id,
      initial: s.initial ? JSON.stringify(s.initial.context) : null,
      role: s.role,
      type: s.type
    });
    console.table(changeset.all.map(row2));
    console.table(cues2.map((c) => ({
      choreo: id2,
      duration: Math.round(c.duration),
      sprite: c.sprite.id ?? c.sprite.role,
      start: Math.round(c.start),
      step: c.kind,
      values: JSON.stringify(c.target ?? c.hold?.values ?? null)
    })));
  }
  /* ---- template ---- */
  host = modifier5((el) => {
    this.element = el;
    setChoreoHost(el, this);
    ensureOrphanStyle();
    if (getComputedStyle(el).position === "static") {
      el.style.position = "relative";
    }
    if (this.args.debug) {
      el.style.outline = "1px dashed #2563eb";
      if (!debugStyle) {
        debugStyle = document.createElement("style");
        debugStyle.textContent = "[data-choreo-orphans] > * { outline: 1px dotted #dc2626 !important; }";
        document.head.appendChild(debugStyle);
      }
    }
    return () => {
      setChoreoHost(el, void 0);
      this.element = void 0;
    };
  });
  layer = modifier5((el) => {
    this.orphanLayer = el;
    return () => {
      this.orphanLayer = void 0;
    };
  });
  raised = modifier5((el) => {
    this.raisedLayer = el;
    return () => {
      this.raisedLayer = void 0;
    };
  });
  tethers = modifier5((el) => {
    this.tetherLayer = el;
    return () => {
      this.tetherLayer = void 0;
    };
  });
  static {
    setComponentTemplate4(precompileTemplate4('\n    {{this.renderDetector}}\n    <div data-choreo={{if @id @id ""}} {{this.host}} ...attributes>\n      <div data-choreo-orphans style="position:absolute;inset:0;pointer-events:none;overflow:visible" {{this.layer}}></div>\n      {{!-- the elevated layer: where c.Raise promotes the living \u2014 above every\n          stacking context and clip in the region (\xA76.3) --}}\n      <div data-choreo-raised style="position:absolute;inset:0;pointer-events:none;overflow:visible;z-index:2147483000" {{this.raised}}></div>\n      {{!-- the wires: geometry drawn between sprites, every frame (\xA76.1) --}}\n      <svg data-choreo-tethers style="position:absolute;inset:0;width:100%;height:100%;pointer-events:none;overflow:visible" {{this.tethers}}></svg>\n      {{yield this.context}}\n    </div>\n  ', {
      strictMode: true
    }), this);
  }
};

// dist/choreo/arming.js
import { tracked as tracked3 } from "@glimmer/tracking";
var Armed = class {
  static {
    decorateFieldV2(this.prototype, "on", [tracked3], function() {
      return false;
    });
  }
  #on = (initializeDeferredDecorator(this, "on"), void 0);
};
var busy = (run) => Boolean(run) && !run.isDone() && !run.standing;
function createArming(options = {}) {
  const {
    deadline = 4e3,
    onStandDown
  } = options;
  const state = new Armed();
  let generation = 0;
  const settlers = [];
  const standDown = () => {
    if (state.on) {
      state.on = false;
    }
    onStandDown?.();
    settlers.splice(0).forEach((resolve3) => resolve3());
  };
  const watch = (gen, region) => {
    const started = performance.now();
    const latch = (run) => {
      void run.finished.then(() => {
        if (gen !== generation) {
          return;
        }
        const current2 = region.run;
        if (current2 && current2 !== run && busy(current2)) {
          latch(current2);
          return;
        }
        standDown();
      });
    };
    const look = () => {
      if (!state.on || gen !== generation) {
        return;
      }
      const run = region.run;
      if (busy(run)) {
        latch(run);
        return;
      }
      if (performance.now() - started > deadline) {
        standDown();
        return;
      }
      requestAnimationFrame(look);
    };
    requestAnimationFrame(look);
  };
  return {
    active: () => state.on,
    begin(region) {
      state.on = true;
      watch(++generation, region);
    },
    end() {
      generation++;
      standDown();
    },
    settled() {
      if (!state.on) {
        return Promise.resolve();
      }
      return new Promise((resolve3) => settlers.push(resolve3));
    }
  };
}

// dist/choreo/shake.js
function mulberry32(seed) {
  let a = seed | 0;
  return () => {
    a = a + 1831565813 | 0;
    let t = Math.imul(a ^ a >>> 15, 1 | a);
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
}
var TAU = Math.PI * 2;
function shake(spec) {
  const {
    amp,
    decay,
    freq,
    roll = 0,
    seed = 1
  } = spec;
  const phase = (k) => TAU * mulberry32(seed + k)();
  const [p1, p2, p3, p4, p5] = [phase(1), phase(2), phase(3), phase(4), phase(5)];
  return ({
    elapsed
  }) => {
    const tau = Math.max(0, elapsed);
    const envelope = decay > 0 ? Math.exp(-tau / decay) : 0;
    const w = TAU * freq * tau;
    return {
      rotate: roll * envelope * Math.sin(0.71 * w + p5),
      x: amp * envelope * (0.62 * Math.sin(w + p1) + 0.38 * Math.sin(2.13 * w + p2)),
      y: amp * envelope * (0.62 * Math.sin(0.93 * w + p3) + 0.38 * Math.sin(1.71 * w + p4))
    };
  };
}

// dist/choreo/space.js
var ORIGIN = {
  x: 0,
  y: 0
};
function appliedCamera(cam2, aim = ORIGIN) {
  return {
    x: cam2.x + (1 - cam2.zoom) * aim.x,
    y: cam2.y + (1 - cam2.zoom) * aim.y
  };
}
function toPage(local, cam2, aim = ORIGIN, scroll2 = ORIGIN) {
  const applied = appliedCamera(cam2, aim);
  return {
    height: local.height * cam2.zoom,
    width: local.width * cam2.zoom,
    x: (local.x - scroll2.x) * cam2.zoom + applied.x,
    y: (local.y - scroll2.y) * cam2.zoom + applied.y
  };
}
function toLocal(page, cam2, aim = ORIGIN, scroll2 = ORIGIN) {
  const applied = appliedCamera(cam2, aim);
  return {
    height: page.height / cam2.zoom,
    width: page.width / cam2.zoom,
    x: (page.x - applied.x) / cam2.zoom + scroll2.x,
    y: (page.y - applied.y) / cam2.zoom + scroll2.y
  };
}

// dist/dom/scroll/utils/can-use-native-timeline.js
function canUseNativeTimeline(target) {
  if (typeof window === "undefined") {
    return false;
  }
  return target ? supportsViewTimeline() : supportsScrollTimeline();
}

// dist/dom/scroll/info.js
var maxElapsed2 = 50;
var createAxisInfo = () => ({
  current: 0,
  offset: [],
  progress: 0,
  scrollLength: 0,
  targetOffset: 0,
  targetLength: 0,
  containerLength: 0,
  velocity: 0
});
var createScrollInfo = () => ({
  time: 0,
  x: createAxisInfo(),
  y: createAxisInfo()
});
var keys = {
  x: {
    length: "Width",
    position: "Left"
  },
  y: {
    length: "Height",
    position: "Top"
  }
};
function updateAxisInfo(element, axisName, info, time2) {
  const axis = info[axisName];
  const {
    length,
    position
  } = keys[axisName];
  const prev = axis.current;
  const prevTime = info.time;
  axis.current = Math.abs(element[`scroll${position}`]);
  axis.scrollLength = element[`scroll${length}`] - element[`client${length}`];
  axis.offset.length = 0;
  axis.offset[0] = 0;
  axis.offset[1] = axis.scrollLength;
  axis.progress = progress(0, axis.scrollLength, axis.current);
  const elapsed = time2 - prevTime;
  axis.velocity = elapsed > maxElapsed2 ? 0 : velocityPerSecond(axis.current - prev, elapsed);
}
function updateScrollInfo(element, info, time2) {
  updateAxisInfo(element, "x", info, time2);
  updateAxisInfo(element, "y", info, time2);
  info.time = time2;
}

// dist/dom/scroll/offsets/inset.js
function calcInset(element, container) {
  const inset = {
    x: 0,
    y: 0
  };
  let current2 = element;
  while (current2 && current2 !== container) {
    if (isHTMLElement(current2)) {
      inset.x += current2.offsetLeft;
      inset.y += current2.offsetTop;
      current2 = current2.offsetParent;
    } else if (current2.tagName === "svg") {
      const svgBoundingBox = current2.getBoundingClientRect();
      current2 = current2.parentElement;
      const parentBoundingBox = current2.getBoundingClientRect();
      inset.x += svgBoundingBox.left - parentBoundingBox.left;
      inset.y += svgBoundingBox.top - parentBoundingBox.top;
    } else if (current2 instanceof SVGGraphicsElement) {
      const {
        x,
        y
      } = current2.getBBox();
      inset.x += x;
      inset.y += y;
      let svg = null;
      let parent = current2.parentNode;
      while (!svg) {
        if (parent.tagName === "svg") {
          svg = parent;
        }
        parent = current2.parentNode;
      }
      current2 = svg;
    } else {
      break;
    }
  }
  return inset;
}

// dist/dom/scroll/offsets/edge.js
var namedEdges = {
  start: 0,
  center: 0.5,
  end: 1
};
function resolveEdge(edge, length, inset = 0) {
  let delta = 0;
  if (edge in namedEdges) {
    edge = namedEdges[edge];
  }
  if (typeof edge === "string") {
    const asNumber2 = parseFloat(edge);
    if (edge.endsWith("px")) {
      delta = asNumber2;
    } else if (edge.endsWith("%")) {
      edge = asNumber2 / 100;
    } else if (edge.endsWith("vw")) {
      delta = asNumber2 / 100 * document.documentElement.clientWidth;
    } else if (edge.endsWith("vh")) {
      delta = asNumber2 / 100 * document.documentElement.clientHeight;
    } else {
      edge = asNumber2;
    }
  }
  if (typeof edge === "number") {
    delta = length * edge;
  }
  return inset + delta;
}

// dist/dom/scroll/offsets/offset.js
var defaultOffset2 = [0, 0];
function resolveOffset(offset, containerLength, targetLength, targetInset) {
  let offsetDefinition = Array.isArray(offset) ? offset : defaultOffset2;
  let targetPoint = 0;
  let containerPoint = 0;
  if (typeof offset === "number") {
    offsetDefinition = [offset, offset];
  } else if (typeof offset === "string") {
    offset = offset.trim();
    if (offset.includes(" ")) {
      offsetDefinition = offset.split(" ");
    } else {
      offsetDefinition = [offset, namedEdges[offset] ? offset : `0`];
    }
  }
  targetPoint = resolveEdge(offsetDefinition[0], targetLength, targetInset);
  containerPoint = resolveEdge(offsetDefinition[1], containerLength);
  return targetPoint - containerPoint;
}

// dist/dom/scroll/offsets/presets.js
var ScrollOffset = {
  Enter: [[0, 1], [1, 1]],
  Exit: [[0, 0], [1, 0]],
  Any: [[1, 0], [0, 1]],
  All: [[0, 0], [1, 1]]
};

// dist/dom/scroll/offsets/index.js
var point = {
  x: 0,
  y: 0
};
function getTargetSize(target) {
  return "getBBox" in target && target.tagName !== "svg" ? target.getBBox() : {
    width: target.clientWidth,
    height: target.clientHeight
  };
}
function resolveOffsets(container, info, options) {
  const {
    offset: offsetDefinition = ScrollOffset.All
  } = options;
  const {
    target = container,
    axis = "y"
  } = options;
  const lengthLabel = axis === "y" ? "height" : "width";
  const inset = target !== container ? calcInset(target, container) : point;
  const targetSize = target === container ? {
    width: container.scrollWidth,
    height: container.scrollHeight
  } : getTargetSize(target);
  const containerSize = {
    width: container.clientWidth,
    height: container.clientHeight
  };
  info[axis].offset.length = 0;
  let hasChanged = !info[axis].interpolate;
  const numOffsets = offsetDefinition.length;
  for (let i = 0; i < numOffsets; i++) {
    const offset = resolveOffset(offsetDefinition[i], containerSize[lengthLabel], targetSize[lengthLabel], inset[axis]);
    if (!hasChanged && offset !== info[axis].interpolatorOffsets[i]) {
      hasChanged = true;
    }
    info[axis].offset[i] = offset;
  }
  if (hasChanged) {
    info[axis].interpolate = interpolate(info[axis].offset, defaultOffset(offsetDefinition), {
      clamp: false
    });
    info[axis].interpolatorOffsets = [...info[axis].offset];
  }
  info[axis].progress = clamp(0, 1, info[axis].interpolate(info[axis].current));
}

// dist/dom/scroll/on-scroll-handler.js
function measure2(container, target = container, info) {
  info.x.targetOffset = 0;
  info.y.targetOffset = 0;
  if (target !== container) {
    let node = target;
    while (node && node !== container) {
      info.x.targetOffset += node.offsetLeft;
      info.y.targetOffset += node.offsetTop;
      node = node.offsetParent;
    }
  }
  info.x.targetLength = target === container ? target.scrollWidth : target.clientWidth;
  info.y.targetLength = target === container ? target.scrollHeight : target.clientHeight;
  info.x.containerLength = container.clientWidth;
  info.y.containerLength = container.clientHeight;
  if (true) {
    if (container && target && target !== container && container !== document.documentElement && container !== document.scrollingElement && container !== document.body) {
      warnOnce(getComputedStyle(container).position !== "static", "Please ensure that the container has a non-static position, like 'relative', 'fixed', or 'absolute' to ensure scroll offset is calculated correctly.");
    }
  }
}
function createOnScrollHandler(element, onScroll, info, options = {}) {
  return {
    measure: (time2) => {
      measure2(element, options.target, info);
      updateScrollInfo(element, info, time2);
      if (options.offset || options.target) {
        resolveOffsets(element, info, options);
      }
    },
    notify: () => onScroll(info)
  };
}

// dist/dom/scroll/track.js
var scrollListeners = /* @__PURE__ */ new WeakMap();
var resizeListeners = /* @__PURE__ */ new WeakMap();
var onScrollHandlers = /* @__PURE__ */ new WeakMap();
var scrollSize = /* @__PURE__ */ new WeakMap();
var dimensionCheckProcesses = /* @__PURE__ */ new WeakMap();
var getEventTarget = (element) => element === document.scrollingElement ? window : element;
function scrollInfo(onScroll, {
  container = document.scrollingElement,
  trackContentSize = false,
  ...options
} = {}) {
  if (!container) {
    return noop;
  }
  let containerHandlers = onScrollHandlers.get(container);
  if (!containerHandlers) {
    containerHandlers = /* @__PURE__ */ new Set();
    onScrollHandlers.set(container, containerHandlers);
  }
  const info = createScrollInfo();
  const containerHandler = createOnScrollHandler(container, onScroll, info, options);
  containerHandlers.add(containerHandler);
  if (!scrollListeners.has(container)) {
    const measureAll = () => {
      for (const handler of containerHandlers) {
        handler.measure(frameData.timestamp);
      }
      frame.preUpdate(notifyAll2);
    };
    const notifyAll2 = () => {
      for (const handler of containerHandlers) {
        handler.notify();
      }
    };
    const listener2 = () => frame.read(measureAll);
    scrollListeners.set(container, listener2);
    const target = getEventTarget(container);
    window.addEventListener("resize", listener2);
    if (container !== document.documentElement) {
      resizeListeners.set(container, resize(container, listener2));
    }
    target.addEventListener("scroll", listener2);
    listener2();
  }
  if (trackContentSize && !dimensionCheckProcesses.has(container)) {
    const listener2 = scrollListeners.get(container);
    const size = {
      width: container.scrollWidth,
      height: container.scrollHeight
    };
    scrollSize.set(container, size);
    const checkScrollDimensions = () => {
      const newWidth = container.scrollWidth;
      const newHeight = container.scrollHeight;
      if (size.width !== newWidth || size.height !== newHeight) {
        listener2();
        size.width = newWidth;
        size.height = newHeight;
      }
    };
    const dimensionCheckProcess = frame.read(checkScrollDimensions, true);
    dimensionCheckProcesses.set(container, dimensionCheckProcess);
  }
  const listener = scrollListeners.get(container);
  frame.read(listener, false, true);
  return () => {
    cancelFrame(listener);
    const currentHandlers = onScrollHandlers.get(container);
    if (!currentHandlers) {
      return;
    }
    currentHandlers.delete(containerHandler);
    if (currentHandlers.size) {
      return;
    }
    const scrollListener = scrollListeners.get(container);
    scrollListeners.delete(container);
    if (scrollListener) {
      getEventTarget(container).removeEventListener("scroll", scrollListener);
      resizeListeners.get(container)?.();
      window.removeEventListener("resize", scrollListener);
    }
    const dimensionCheckProcess = dimensionCheckProcesses.get(container);
    if (dimensionCheckProcess) {
      cancelFrame(dimensionCheckProcess);
      dimensionCheckProcesses.delete(container);
    }
    scrollSize.delete(container);
  };
}

// dist/dom/scroll/utils/offset-to-range.js
var presets = [[ScrollOffset.Enter, "entry"], [ScrollOffset.Exit, "exit"], [ScrollOffset.Any, "cover"], [ScrollOffset.All, "contain"]];
var stringToProgress = {
  start: 0,
  end: 1
};
function parseStringOffset(s) {
  const parts = s.trim().split(/\s+/);
  if (parts.length !== 2) {
    return void 0;
  }
  const a = stringToProgress[parts[0]];
  const b = stringToProgress[parts[1]];
  if (a === void 0 || b === void 0) {
    return void 0;
  }
  return [a, b];
}
function normaliseOffset(offset) {
  if (offset.length !== 2) {
    return void 0;
  }
  const result = [];
  for (const item of offset) {
    if (Array.isArray(item)) {
      result.push(item);
    } else if (typeof item === "string") {
      const parsed = parseStringOffset(item);
      if (!parsed) {
        return void 0;
      }
      result.push(parsed);
    } else {
      return void 0;
    }
  }
  return result;
}
function matchesPreset(offset, preset) {
  const normalised = normaliseOffset(offset);
  if (!normalised) {
    return false;
  }
  for (let i = 0; i < 2; i++) {
    const o = normalised[i];
    const p = preset[i];
    if (o[0] !== p[0] || o[1] !== p[1]) {
      return false;
    }
  }
  return true;
}
function offsetToViewTimelineRange(offset) {
  if (!offset) {
    return {
      rangeStart: "contain 0%",
      rangeEnd: "contain 100%"
    };
  }
  for (const [preset, name] of presets) {
    if (matchesPreset(offset, preset)) {
      return {
        rangeStart: `${name} 0%`,
        rangeEnd: `${name} 100%`
      };
    }
  }
  return void 0;
}

// dist/dom/scroll/utils/get-timeline.js
var timelineCache = /* @__PURE__ */ new Map();
function scrollTimelineFallback(options) {
  const currentTime = {
    value: 0
  };
  const cancel = scrollInfo((info) => {
    currentTime.value = info[options.axis].progress * 100;
  }, options);
  return {
    currentTime,
    cancel
  };
}
function getTimeline({
  source,
  container,
  ...options
}) {
  const {
    axis
  } = options;
  if (source) {
    container = source;
  }
  let containerCache = timelineCache.get(container);
  if (!containerCache) {
    containerCache = /* @__PURE__ */ new Map();
    timelineCache.set(container, containerCache);
  }
  const targetKey = options.target ?? "self";
  let targetCache = containerCache.get(targetKey);
  if (!targetCache) {
    targetCache = {};
    containerCache.set(targetKey, targetCache);
  }
  const axisKey = axis + (options.offset ?? []).join(",");
  if (!targetCache[axisKey]) {
    if (options.target && canUseNativeTimeline(options.target)) {
      const range = offsetToViewTimelineRange(options.offset);
      if (range) {
        targetCache[axisKey] = new ViewTimeline({
          subject: options.target,
          axis
        });
      } else {
        targetCache[axisKey] = scrollTimelineFallback({
          container,
          ...options
        });
      }
    } else if (canUseNativeTimeline()) {
      targetCache[axisKey] = new ScrollTimeline({
        source: container,
        axis
      });
    } else {
      targetCache[axisKey] = scrollTimelineFallback({
        container,
        ...options
      });
    }
  }
  return targetCache[axisKey];
}

// dist/dom/scroll/attach-animation.js
function attachToAnimation(animation, options) {
  const timeline = getTimeline(options);
  const range = options.target ? offsetToViewTimelineRange(options.offset) : void 0;
  const useNative = options.target ? canUseNativeTimeline(options.target) && !!range : canUseNativeTimeline();
  return animation.attachTimeline({
    timeline: useNative ? timeline : void 0,
    ...range && useNative && {
      rangeStart: range.rangeStart,
      rangeEnd: range.rangeEnd
    },
    observe: (valueAnimation) => {
      valueAnimation.pause();
      return observeTimeline((progress2) => {
        valueAnimation.time = valueAnimation.iterationDuration * progress2;
      }, timeline);
    }
  });
}

// dist/dom/scroll/utils/is-element-tracking.js
function isElementTracking(options) {
  return options && (options.target || options.offset);
}

// dist/dom/scroll/attach-function.js
function isOnScrollWithInfo(onScroll) {
  return onScroll.length === 2;
}
function attachToFunction(onScroll, options) {
  if (isOnScrollWithInfo(onScroll) || isElementTracking(options)) {
    return scrollInfo((info) => {
      onScroll(info[options.axis].progress, info);
    }, options);
  } else {
    return observeTimeline(onScroll, getTimeline(options));
  }
}

// dist/dom/scroll/index.js
function scroll(onScroll, {
  axis = "y",
  container = document.scrollingElement,
  ...options
} = {}) {
  if (!container) {
    return noop;
  }
  const optionsWithDefaults = {
    axis,
    container,
    ...options
  };
  return typeof onScroll === "function" ? attachToFunction(onScroll, optionsWithDefaults) : attachToAnimation(onScroll, optionsWithDefaults);
}

// dist/dom/viewport.js
var thresholds = {
  some: 0,
  all: 1
};
function inView(elementOrSelector, onStart, {
  root,
  margin: rootMargin,
  amount = "some"
} = {}) {
  const elements = resolveElements(elementOrSelector);
  const activeIntersections = /* @__PURE__ */ new WeakMap();
  const onIntersectionChange = (entries) => {
    entries.forEach((entry) => {
      const onEnd = activeIntersections.get(entry.target);
      if (entry.isIntersecting === Boolean(onEnd)) {
        return;
      }
      if (entry.isIntersecting) {
        const newOnEnd = onStart(entry.target, entry);
        if (typeof newOnEnd === "function") {
          activeIntersections.set(entry.target, newOnEnd);
        } else {
          observer2.unobserve(entry.target);
        }
      } else if (typeof onEnd === "function") {
        onEnd(entry);
        activeIntersections.delete(entry.target);
      }
    });
  };
  const observer2 = new IntersectionObserver(onIntersectionChange, {
    root,
    rootMargin,
    threshold: typeof amount === "number" ? amount : thresholds[amount]
  });
  elements.forEach((element) => observer2.observe(element));
  return () => observer2.disconnect();
}

// dist/film/clip.js
import { array } from "@ember/helper";
import Component5 from "@glimmer/component";

// dist/motion.js
import { registerDestructor as registerDestructor2 } from "@ember/destroyable";
import { schedule as schedule2 } from "@ember/runloop";
import Modifier from "ember-modifier";
setPostRender((fn3) => schedule2("afterRender", null, fn3));
var MotionModifier = class extends Modifier {
  node = new MotionNode();
  constructor(owner, args) {
    super(owner, args);
    registerDestructor2(this, () => this.node.destroy());
  }
  modify(element, _pos, named) {
    this.node.update(element, named);
  }
};

// dist/film/clip.js
import { precompileTemplate as precompileTemplate5 } from "@ember/template-compilation";
import { setComponentTemplate as setComponentTemplate5 } from "@ember/component";
var Clip = class extends Component5 {
  /** a pip is placed by the score, in percent of the frame */
  get place() {
    const c = this.args.spec;
    if (c.fit !== "pip") {
      return "";
    }
    return [`left:${c.x ?? 66}%`, `top:${c.y ?? 10}%`, `width:${c.w ?? 30}%`, `border-radius:${c.radius ?? 0}%`, `--cf-pip-fade:${c.fade ?? 0.4}s`].join(";");
  }
  /** a pip fades; the editorial card is wiped in and out */
  get isPip() {
    return this.args.spec.fit === "pip";
  }
  /** seconds a pip takes to arrive and to go */
  get fade() {
    return this.args.spec.fade ?? 0.4;
  }
  get muted() {
    return !(this.args.spec.volume && this.args.spec.volume > 0);
  }
  get volume() {
    return Math.max(0, Math.min(1, this.args.spec.volume ?? 0));
  }
  static {
    setComponentTemplate5(precompileTemplate5('\n    <Choreo @id="clip" @releaseOnSeek={{true}} class="cf-clip is-{{if @spec.fit @spec.fit "inset"}} is-{{@state}}" as |g|>\n      {{#each (array @key) key="@identity"}}\n        <figure style={{this.place}} {{motion id="clip" role="clip"}}>\n          {{#if (eq @spec.kind "video")}}\n            <video src={{@src}} muted={{this.muted}} playsinline preload="auto" {{@mount}}></video>\n          {{else if (eq @spec.kind "image")}}\n            <img src={{@src}} alt {{@mount}} />\n          {{else}}\n            {{#if @freeze}}\n              <img src={{@freeze}} alt {{@mount}} />\n            {{/if}}\n          {{/if}}\n          {{#if @spec.caption}}\n            <figcaption>\n              <span class="cf-clip-cap">{{@spec.caption}}</span>\n              {{#if @spec.credit}}\n                <span class="cf-clip-cr">{{@spec.credit}}</span>\n              {{/if}}\n            </figcaption>\n          {{/if}}\n        </figure>\n      {{/each}}\n      {{#if this.isPip}}\n        {{!-- A PIP FADES. It is a layer, not a photograph pinned to the\n        page, so it arrives and leaves the way a layer does \u2014 on its own\n        length, which the score sets. --}}\n        <g.Tween @of={{g.inserted "clip"}} @opacity={{array 0 1}} @scale={{array 1.04 1}} @duration={{this.fade}} @ease="easeOut" />\n        <g.Tween @of={{g.removed "clip"}} @opacity={{0}} @duration={{this.fade}} @ease="easeIn" />\n      {{else}}\n        <g.Tween @of={{g.inserted "clip"}} @clipPath={{array "inset(0 100% 0 0)" "inset(0 0% 0 0)"}} @duration={{0.62}} @ease={{array 0.22 1 0.36 1}} />\n        <g.Tween @of={{g.removed "clip"}} @opacity={{0}} @duration={{0.24}} @ease="easeIn" />\n      {{/if}}\n    </Choreo>\n  ', {
      strictMode: true,
      scope: () => ({
        Choreo,
        array,
        motion: MotionModifier,
        eq
      })
    }), this);
  }
};
function eq(a, b) {
  return a === b;
}

// dist/film/film.js
import { on as on4 } from "@ember/modifier";
import Component15 from "@glimmer/component";
import { tracked as tracked4 } from "@glimmer/tracking";
import { modifier as modifier9 } from "ember-modifier";

// dist/film/clips.js
function clipWindow(spec, beatStart2, nextStart) {
  if (spec.for !== void 0) {
    return spec.for;
  }
  if (spec.out !== void 0) {
    return (spec.out - (spec.in ?? 0)) / (spec.rate ?? 1);
  }
  return Math.max(0, nextStart - beatStart2 - (spec.at ?? 0));
}
function resolveClip(beats, beatStart2, film, index, total) {
  for (let i = Math.min(index, beats.length - 1); i >= 0; i -= 1) {
    const spec = beats[i].clip;
    if (!spec) {
      continue;
    }
    const start2 = beatStart2(i) + (spec.at ?? 0);
    if (film < start2) {
      continue;
    }
    const next2 = i + 1 < beats.length ? beatStart2(i + 1) : total;
    const window2 = clipWindow(spec, beatStart2(i), next2);
    const since = film - start2;
    const rate = spec.rate ?? 1;
    const inPoint = spec.in ?? 0;
    if (since < window2) {
      return {
        index: i,
        since,
        source: inPoint + since * rate,
        spec,
        state: "active"
      };
    }
    const end = spec.end ?? "remove";
    if (end === "remove") {
      return null;
    }
    return {
      index: i,
      since,
      source: end === "hold" ? inPoint + window2 * rate : null,
      spec,
      state: end === "hold" ? "held" : "frozen"
    };
  }
  return null;
}

// dist/film/frames.js
function frameCam(cam2, port) {
  if (!cam2.on || !port.frame) {
    return cam2;
  }
  const box = port.frame(cam2.on);
  if (!box) {
    return cam2;
  }
  const zoom = cam2.fit !== void 0 ? cam2.fit / Math.max(box.w, box.h, 1e-3) : cam2.dolly;
  return {
    ...cam2,
    dolly: zoom,
    fx: box.x + (cam2.fx ?? 0),
    lookY: box.y + (cam2.lookY ?? 0)
  };
}
function frameBeats(beats, port) {
  if (!port?.frame || !beats.some((b) => b.cam.on || b.toCam?.on)) {
    return beats;
  }
  return beats.map((b) => b.cam.on || b.toCam?.on ? {
    ...b,
    cam: frameCam(b.cam, port),
    toCam: b.toCam ? frameCam(b.toCam, port) : b.toCam
  } : b);
}

// dist/film/graph/host.js
import Component7 from "@glimmer/component";
import { modifier as modifier7 } from "ember-modifier";

// dist/film/graph/nodes.js
import Component6 from "@glimmer/component";
import { modifier as modifier6 } from "ember-modifier";

// dist/film/math.js
var RAD = Math.PI / 180;
var lerp = (a, b, t) => a + (b - a) * t;
var clamp01 = (v) => Math.max(0, Math.min(1, v));
var smooth = (t) => {
  const k = clamp01(t);
  return k * k * (3 - 2 * k);
};
var hex2 = (h) => [parseInt(h.slice(1, 3), 16) / 255, parseInt(h.slice(3, 5), 16) / 255, parseInt(h.slice(5, 7), 16) / 255];
var luminance = (h) => {
  if (!/^#[0-9a-f]{6}$/i.test(h)) {
    return 1;
  }
  const [r, g, b] = hex2(h);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};
var rgba2 = (h, a) => {
  if (!/^#[0-9a-f]{6}$/i.test(h)) {
    return h;
  }
  const [r, g, b] = hex2(h);
  return `rgba(${Math.round(r * 255)}, ${Math.round(g * 255)}, ${Math.round(b * 255)}, ${a})`;
};
var wrapAngle = (d) => {
  let k = d;
  while (k > Math.PI) {
    k -= Math.PI * 2;
  }
  while (k < -Math.PI) {
    k += Math.PI * 2;
  }
  return k;
};

// dist/film/schedule.js
var TICK = 2;
function totalSecs(beats) {
  return beats.reduce((n, b, i) => n + b.ticks + (i === 0 ? 0 : b.lead ?? 0), 0) * TICK;
}
function secsBefore(beats, index) {
  return beats.slice(0, index).reduce((n, b, i) => n + b.ticks + (i === 0 ? 0 : b.lead ?? 0), 0) * TICK;
}
function beatStart(beats, i) {
  if (i <= 0) {
    return 0;
  }
  return secsBefore(beats, i) + (beats[i].lead ?? 0) * TICK + TICK;
}
function cues(beats) {
  let t = 0;
  const out = [];
  beats.forEach((b, i) => {
    const lead = i === 0 ? 0 : b.lead ?? 0;
    if (lead > 0) {
      out.push({
        action: "air",
        delay: t + TICK,
        index: String(i)
      });
    }
    const at2 = t + lead * TICK;
    t = at2 + b.ticks * TICK;
    out.push({
      action: "beat",
      delay: at2 === 0 ? 0 : at2 + TICK,
      index: String(i)
    });
  });
  return out;
}
function chapterHeads(beats) {
  const heads = [];
  beats.forEach((b, i) => {
    if (heads.length === 0 || beats[heads[heads.length - 1]].ch !== b.ch) {
      heads.push(i);
    }
  });
  return heads;
}
function contents(beats, chapters) {
  const heads = chapterHeads(beats);
  return heads.map((head, i) => {
    const nextHead = heads[i + 1] ?? beats.length;
    const ch = chapters[beats[head].ch] ?? chapters[0];
    return {
      head,
      n: ch.n,
      secs: beats.slice(head, nextHead).reduce((t, b) => t + b.ticks, 0) * TICK,
      shots: nextHead - head,
      title: ch.title
    };
  });
}
function joinInto(beats, i, defaultJoin) {
  const beat = beats[i];
  return beat.cut || beat.join ? beat.join ?? defaultJoin : null;
}
function tailFor(beats, bi) {
  const b = beats[bi];
  const drift = b.toCam ?? {
    ...b.cam,
    dolly: b.cam.dolly * 1.05,
    pitch: b.cam.pitch + 1.4,
    yaw: b.cam.yaw + 6
  };
  const next2 = beats[bi + 1];
  const secs = b.ticks * TICK;
  const sgn = (d) => d < 0 ? -1 : 1;
  const stretch = (key, floor) => {
    const head = b.cam[key] ?? 0;
    const d = (drift[key] ?? 0) - head;
    const nose = next2 ? (next2.cam[key] ?? 0) - head : 0;
    const way = d !== 0 ? sgn(d) : nose !== 0 ? sgn(nose) : 1;
    const reach = !next2 ? Infinity : sgn(nose) === way && nose !== 0 ? Math.abs(nose) : 0;
    const want = Math.min(Math.max(Math.abs(d), floor), Math.max(Math.abs(d), reach));
    return head + way * want;
  };
  const to2 = {
    ...drift,
    dolly: stretch("dolly", b.cam.dolly * Math.min(0.22, 0.022 * secs)),
    ox: stretch("ox", Math.min(0.07, 8e-3 * secs)),
    pitch: stretch("pitch", Math.min(6, 0.45 * secs)),
    yaw: stretch("yaw", Math.min(22, 2 * secs))
  };
  return {
    dolly: to2.dolly,
    fx: to2.fx ?? b.cam.fx ?? 0,
    fz: to2.fz ?? b.cam.fz ?? 0,
    lookY: to2.lookY,
    ox: to2.ox,
    pitch: to2.pitch,
    yaw: to2.yaw
  };
}
function waypoints(beats, recut = false) {
  const pts = [];
  let seg = 1;
  let at2 = 0;
  const push = (w) => {
    at2 += seg;
    pts.push(Math.abs(seg - 1) > 1e-9 ? {
      ...w,
      slots: seg
    } : w);
  };
  for (const [bi, b] of beats.entries()) {
    const splice = b.cut === true || bi === 0 && recut;
    const to2 = tailFor(beats, bi);
    const lead = bi === 0 ? 0 : b.lead ?? 0;
    const prev = pts[pts.length - 1];
    if (lead > 0 && prev) {
      const nl = Math.max(1, Math.round(lead));
      for (let k = 1; k <= nl; k++) {
        const f = k / (nl + 1);
        push({
          dolly: lerp(prev.dolly, b.cam.dolly, f),
          look: {
            x: lerp(prev.look.x, b.cam.fx ?? 0, f),
            y: lerp(prev.look.y, b.cam.lookY, f),
            z: lerp(prev.look.z, b.cam.fz ?? 0, f)
          },
          pitch: lerp(prev.pitch, b.cam.pitch, f),
          x: lerp(prev.x, b.cam.ox ?? 0, f),
          y: 0,
          yaw: lerp(prev.yaw, b.cam.yaw, f)
        });
        seg = lead / nl;
      }
    }
    const n = Math.max(1, Math.round(b.ticks));
    for (let k = 0; k < n; k++) {
      const f = n === 1 ? 0 : k / (n - 1);
      push({
        cut: splice && k === 0 ? true : void 0,
        dolly: lerp(b.cam.dolly, to2.dolly, f),
        look: {
          x: lerp(b.cam.fx ?? 0, to2.fx ?? 0, f),
          y: lerp(b.cam.lookY, to2.lookY, f),
          z: lerp(b.cam.fz ?? 0, to2.fz ?? 0, f)
        },
        pitch: lerp(b.cam.pitch, to2.pitch, f),
        x: lerp(b.cam.ox ?? 0, to2.ox ?? 0, f),
        y: 0,
        yaw: lerp(b.cam.yaw, to2.yaw, f)
      });
      seg = b.ticks / n;
    }
  }
  const rest = totalSecs(beats) / TICK - at2;
  const last = pts[pts.length - 1];
  if (last && rest > 1e-6) {
    seg = rest;
    push({
      dolly: last.dolly,
      look: last.look,
      pitch: last.pitch,
      x: last.x,
      y: last.y,
      yaw: last.yaw
    });
  }
  return pts;
}
function pathSecs(path) {
  return path.reduce((t, w) => t + (w.slots ?? 1), 0) * TICK;
}
function schedule3(beats, chapters, defaultJoin) {
  return {
    beats: beats.map((b, i) => ({
      ch: b.ch,
      id: b.id,
      join: joinInto(beats, i, defaultJoin),
      lead: i === 0 ? 0 : b.lead ?? 0,
      secsBefore: secsBefore(beats, i),
      start: beatStart(beats, i),
      ticks: b.ticks
    })),
    contents: contents(beats, chapters),
    cues: cues(beats),
    total: totalSecs(beats),
    waypoints: waypoints(beats)
  };
}

// dist/film/graph/nodes.js
import { precompileTemplate as precompileTemplate6 } from "@ember/template-compilation";
import { setComponentTemplate as setComponentTemplate6 } from "@ember/component";
var providers2 = /* @__PURE__ */ new WeakMap();
var hosts2 = /* @__PURE__ */ new WeakMap();
function setGraphHost(el, host) {
  if (host) {
    hosts2.set(el, host);
  } else {
    hosts2.delete(el);
  }
}
function collectGraph(el) {
  const out = [];
  for (const child of Array.from(el.children)) {
    const provider = providers2.get(child);
    if (provider) {
      const node = provider.node();
      if (node.kind === "group" || node.kind === "shot") {
        node.children = collectGraph(child);
        if (node.kind === "group") {
          const items = [];
          for (const c of node.children) {
            if (c.kind === "patch") {
              node.patches.push(c.patch);
            } else {
              items.push(c);
            }
          }
          node.children = items;
        }
      } else if (node.kind === "attach") {
        const inner = collectGraph(child);
        const media = inner.find((n) => n.kind === "attach")?.media;
        if (media) {
          node.media = media;
        }
      }
      out.push(node);
    } else {
      out.push(...collectGraph(child));
    }
  }
  return out;
}
function tidy(o) {
  const out = {};
  for (const [k, v] of Object.entries(o)) {
    if (v !== void 0) {
      out[k] = v;
    }
  }
  return out;
}
var GraphNodeComponent = class extends Component6 {
  mark = modifier6((el) => {
    providers2.set(el, this);
    void this.node();
    const host = el.parentElement?.closest("[data-film-graph]");
    (host ? hosts2.get(host) : void 0)?.invalidate();
    return () => {
      providers2.delete(el);
      (host ? hosts2.get(host) : void 0)?.invalidate();
    };
  });
  static {
    setComponentTemplate6(precompileTemplate6("\n    <span hidden data-film-node {{this.mark}}>{{yield}}</span>\n  ", {
      strictMode: true
    }), this);
  }
};
function groupDefaults(args) {
  return tidy({
    bob: args.bob,
    cut: args.cut,
    hold: args.hold,
    lead: args.lead
  });
}
var Spine = class extends GraphNodeComponent {
  node() {
    return {
      children: [],
      defaults: groupDefaults(this.args),
      join: this.args.join,
      kind: "group",
      name: this.args.name,
      over: this.args.over,
      patches: [],
      role: "spine"
    };
  }
};
var Chapter = class extends GraphNodeComponent {
  node() {
    const {
      grade,
      lut,
      n,
      tint,
      tintD,
      title
    } = this.args;
    return {
      chapter: tidy({
        grade,
        lut,
        n,
        tint,
        tintD,
        title
      }),
      children: [],
      defaults: groupDefaults(this.args),
      join: this.args.join,
      kind: "group",
      name: this.args.name,
      over: this.args.over,
      patches: [],
      role: "chapter"
    };
  }
};
var Sequence2 = class extends GraphNodeComponent {
  node() {
    return {
      children: [],
      defaults: groupDefaults(this.args),
      join: this.args.join,
      kind: "group",
      name: this.args.name,
      over: this.args.over,
      patches: [],
      role: "sequence"
    };
  }
};
function cam(a) {
  return tidy({
    dolly: a.zoom ?? a.dolly ?? 1,
    fit: a.fit,
    on: a.on,
    fx: a.x ?? a.fx,
    fz: a.fz,
    lookY: a.y ?? a.lookY ?? 0,
    ox: a.ox,
    pitch: a.pitch ?? 0,
    yaw: a.yaw ?? 0
  });
}
var Shot = class extends GraphNodeComponent {
  node() {
    const a = this.args;
    return {
      cam: cam(a),
      children: [],
      facts: tidy({
        bob: a.bob,
        cut: a.cut,
        dissolve: a.dissolve,
        follow: a.follow,
        hold: a.hold,
        lead: a.lead,
        lift: a.lift,
        quality: a.quality,
        to: a.to
      }),
      id: a.name,
      kind: "shot",
      ticks: a.secs !== void 0 ? a.secs / TICK : a.ticks ?? 1
    };
  }
};
var To = class extends GraphNodeComponent {
  node() {
    return {
      cam: cam(this.args),
      kind: "to"
    };
  }
};
var Eye = class extends GraphNodeComponent {
  node() {
    return {
      eye: tidy({
        at: this.args.from,
        fov: this.args.fov,
        to: this.args.to
      }),
      kind: "eye"
    };
  }
};
var JoinInto = class extends GraphNodeComponent {
  node() {
    const p = this.args.presentation;
    if (typeof p === "string") {
      return {
        dipTo: this.args.to,
        join: p,
        kind: "join",
        over: this.args.over,
        secs: this.args.secs
      };
    }
    return {
      dipTo: this.args.to,
      join: "",
      kind: "join",
      over: this.args.over,
      presentation: p,
      secs: this.args.secs
    };
  }
};
var PatchComponent = class extends GraphNodeComponent {
  node() {
    return {
      kind: "patch",
      patch: tidy(this.patch())
    };
  }
};
var Type = class extends PatchComponent {
  patch() {
    const a = this.args;
    return {
      bare: a.bare,
      gloss: a.gloss,
      kanji: a.word,
      kicker: a.kicker,
      mode: a.mode,
      romaji: a.reading,
      says: a.says
    };
  }
};
var Voice = class extends GraphNodeComponent {
  node() {
    const {
      gain,
      hush,
      line,
      read
    } = this.args;
    return tidy({
      gain,
      hush,
      kind: "voice",
      line,
      read
    });
  }
};
var Stamp = class extends PatchComponent {
  patch() {
    return {
      stamp: tidy({
        at: this.args.at,
        y: this.args.year
      })
    };
  }
};
var Sky = class extends PatchComponent {
  patch() {
    const a = this.args;
    return {
      sky: tidy({
        az: a.az,
        dist: a.dist,
        lines: a.lines,
        opacity: a.opacity,
        size: a.size,
        track: a.track,
        y: a.y
      })
    };
  }
};
var Mark = class extends PatchComponent {
  patch() {
    const a = this.args;
    return {
      mark: tidy({
        at: a.at,
        bearing: a.bearing,
        hold: a.hold,
        lines: a.lines,
        r: a.r,
        size: a.size,
        to: a.to
      })
    };
  }
};
var Trace = class extends PatchComponent {
  patch() {
    return {
      trace: [tidy({
        pts: this.args.pts,
        wide: this.args.wide
      })]
    };
  }
};
var Lineup = class extends PatchComponent {
  patch() {
    return {
      cycle: this.args.steps
    };
  }
};
var Attach2 = class extends GraphNodeComponent {
  node() {
    return tidy({
      at: this.args.at,
      end: this.args.end,
      for: this.args.for,
      kind: "attach"
    });
  }
};
var Insert = class extends GraphNodeComponent {
  node() {
    const {
      caption,
      credit,
      src
    } = this.args;
    return {
      kind: "attach",
      media: {
        caption,
        credit,
        kind: "photo",
        src
      }
    };
  }
};
var Freeze = class extends GraphNodeComponent {
  node() {
    const {
      caption,
      credit,
      fit
    } = this.args;
    return {
      kind: "attach",
      media: tidy({
        caption,
        credit,
        fit,
        kind: "freeze"
      })
    };
  }
};
var Inset = class extends GraphNodeComponent {
  node() {
    const a = this.args;
    return {
      at: a.at,
      end: a.end,
      for: a.for,
      kind: "attach",
      media: tidy({
        fade: a.fade,
        fit: "pip",
        in: a.in,
        kind: a.still ? "image" : "video",
        out: a.out,
        radius: a.radius,
        rate: a.rate,
        src: a.src,
        volume: a.volume,
        w: a.w,
        x: a.x,
        y: a.y
      })
    };
  }
};
var Video = class extends GraphNodeComponent {
  node() {
    const a = this.args;
    return {
      kind: "attach",
      media: tidy({
        caption: a.caption,
        credit: a.credit,
        fit: a.fit,
        in: a.in,
        kind: a.still ? "image" : "video",
        out: a.out,
        rate: a.rate,
        src: a.src,
        volume: a.volume
      })
    };
  }
};

// dist/film/graph/adjust.js
var Adjustment = class extends PatchComponent {
};
var Filter = class extends Adjustment {
};
var Look = class extends Filter {
  patch() {
    return {
      grade: this.args.grade,
      look: this.args.look,
      lut: this.args.lut
    };
  }
};
var Weather = class extends Adjustment {
  patch() {
    const a = this.args;
    return {
      haze: a.haze,
      hours: a.hours,
      hoursOver: a.over,
      lightning: a.lightning,
      rain: a.rain,
      theme: a.theme,
      wx: a.wx,
      wxCut: a.wxCut
    };
  }
};
var Winter = class extends Adjustment {
  patch() {
    if (this.args.off) {
      return {
        winter: null
      };
    }
    return {
      winter: {
        gust: this.args.gust ?? 0,
        pack: this.args.pack ?? 0
      }
    };
  }
};
var Sun = class extends Adjustment {
  patch() {
    return {
      sun: {
        az: this.args.az,
        el: this.args.el
      }
    };
  }
};
var Light = class extends Adjustment {
  patch() {
    return {
      rim: this.args.rim
    };
  }
};
var Set2 = class extends Adjustment {
  patch() {
    return {
      city: this.args.city,
      grass: this.args.grass
    };
  }
};
var Build = class extends Adjustment {
  patch() {
    const a = this.args;
    return {
      build: a.clock,
      buildBy: a.by,
      settle: a.settle,
      style: a.subject
    };
  }
};
var Mix = class extends Adjustment {
  patch() {
    const {
      music,
      sfx,
      voice,
      wx
    } = this.args;
    const mix2 = {};
    if (music !== void 0) {
      mix2.music = music;
    }
    if (sfx !== void 0) {
      mix2.sfx = sfx;
    }
    if (voice !== void 0) {
      mix2.voice = voice;
    }
    if (wx !== void 0) {
      mix2.wx = wx;
    }
    return {
      mix: mix2
    };
  }
};
var IFRAME_PICTURE = {
  Build,
  Light,
  Look,
  Set: Set2,
  Sun,
  Weather,
  Winter
};
var SOUND = {
  Mix
};

// dist/film/graph/compile.js
function tidy2(o) {
  const out = {};
  for (const [k, v] of Object.entries(o)) {
    if (v !== void 0) {
      out[k] = v;
    }
  }
  return out;
}
function compileGraph(root) {
  const beats = [];
  const chapters = [];
  const voSecs = {};
  const voGain = {};
  const presentations = {};
  let ch = 0;
  const walk = (group, inherited, joinDefault, overDefault) => {
    if (group.role === "chapter" && group.chapter) {
      chapters.push(tidy2(group.chapter));
      ch = chapters.length - 1;
    }
    const scope = [...inherited, group.defaults, ...group.patches];
    const seam = group.role === "spine" ? void 0 : group.join ?? joinDefault;
    const deep = group.role === "spine" ? void 0 : group.over ?? overDefault;
    let pending2;
    for (const node of group.children) {
      if (node.kind === "group") {
        walk(node, scope, seam, deep);
        pending2 = void 0;
      } else if (node.kind === "join") {
        if (!node.presentation && node.secs !== void 0) {
          presentations[node.join] = {
            secs: node.secs
          };
          pending2 = node;
        } else if (node.presentation) {
          const name = `presentation:${Object.keys(presentations).length + 1}`;
          presentations[name] = {
            component: node.presentation,
            over: node.over,
            secs: node.secs ?? 1
          };
          pending2 = {
            ...node,
            join: name
          };
        } else {
          pending2 = node;
        }
      } else if (node.kind === "shot") {
        beats.push(row(node, scope, pending2 ?? seam, deep, ch, voSecs, voGain));
        pending2 = void 0;
      }
    }
  };
  walk(root, []);
  return {
    beats,
    chapters,
    defaultJoin: root.join,
    defaultOver: root.over,
    presentations,
    voGain,
    voSecs
  };
}
function row(shot, scope, seam, deep, ch, voSecs, voGain) {
  let beat = {
    cam: shot.cam,
    ch,
    id: shot.id,
    mode: "clear",
    ticks: shot.ticks
  };
  const merge = (p) => {
    beat = {
      ...beat,
      ...tidy2(p)
    };
  };
  for (const p of scope) {
    merge(p);
  }
  merge(shot.facts);
  if (seam) {
    if (typeof seam === "string") {
      merge({
        join: seam,
        over: deep
      });
    } else {
      merge({
        dipTo: seam.dipTo,
        join: seam.join,
        over: seam.over ?? deep
      });
    }
  }
  const traces = [];
  for (const node of shot.children) {
    switch (node.kind) {
      case "patch":
        if (node.patch.trace) {
          traces.push(...node.patch.trace);
          const {
            trace: _trace,
            ...rest
          } = node.patch;
          merge(rest);
        } else {
          merge(node.patch);
        }
        break;
      case "to":
        merge({
          toCam: node.cam
        });
        break;
      case "eye":
        merge({
          eye: node.eye
        });
        break;
      case "voice":
        merge({
          hush: node.hush,
          vo: node.line
        });
        if (node.read !== void 0) {
          voSecs[shot.id] = node.read;
        }
        if (node.gain !== void 0) {
          voGain[shot.id] = node.gain;
        }
        break;
      case "attach":
        if (node.media?.kind === "photo") {
          const {
            kind: _kind,
            ...photo
          } = node.media;
          merge({
            photo
          });
        } else if (node.media) {
          const {
            kind,
            ...rest
          } = node.media;
          merge({
            clip: tidy2({
              ...rest,
              at: node.at,
              end: node.end,
              for: node.for,
              kind
            })
          });
        }
        break;
    }
  }
  if (traces.length) {
    merge({
      trace: traces
    });
  }
  return tidy2(beat);
}

// dist/film/graph/host.js
import { precompileTemplate as precompileTemplate7 } from "@ember/template-compilation";
import { setComponentTemplate as setComponentTemplate7 } from "@ember/component";
var VOCABULARY = {
  Attach: Attach2,
  Chapter,
  Eye,
  Freeze,
  Insert,
  Inset,
  Join: JoinInto,
  Lineup,
  Mark,
  Sequence: Sequence2,
  Shot,
  Sky,
  Spine,
  Stamp,
  To,
  Trace,
  Type,
  Video,
  Voice,
  picture: IFRAME_PICTURE,
  sound: SOUND
};
var FilmGraph = class extends Component7 {
  element;
  pending = 0;
  invalidate() {
    if (this.pending || !this.element) {
      return;
    }
    this.pending = requestAnimationFrame(() => {
      this.pending = 0;
      this.args.onCompile(this.compile());
    });
  }
  /** the tree under the host, compiled; null without a spine */
  compile() {
    if (!this.element) {
      return null;
    }
    const spine = collectGraph(this.element).find((n) => n.kind === "group" && n.role === "spine");
    return spine ? compileGraph(spine) : null;
  }
  host = modifier7((el) => {
    this.element = el;
    setGraphHost(el, this);
    this.invalidate();
    return () => {
      if (this.pending) {
        cancelAnimationFrame(this.pending);
        this.pending = 0;
      }
      setGraphHost(el, void 0);
      this.element = void 0;
    };
  });
  static {
    setComponentTemplate7(precompileTemplate7('\n    {{!-- contents, not a box: the film page lays out what the block\n        renders, and the host must not stand between them --}}\n    <div data-film-graph style="display:contents" {{this.host}}>\n      {{yield VOCABULARY}}\n    </div>\n  ', {
      strictMode: true,
      scope: () => ({
        VOCABULARY
      })
    }), this);
  }
};

// dist/film/joins.js
import Component8 from "@glimmer/component";
import { modifier as modifier8 } from "ember-modifier";
import { precompileTemplate as precompileTemplate8 } from "@ember/template-compilation";
import { setComponentTemplate as setComponentTemplate8 } from "@ember/component";
var retire = modifier8((el, [seekable]) => {
  if (seekable) {
    return;
  }
  const done = () => {
    el.style.display = "none";
  };
  el.addEventListener("animationend", done);
  el.addEventListener("animationcancel", done);
  const failsafe = window.setTimeout(done, 1400);
  return () => {
    window.clearTimeout(failsafe);
    el.removeEventListener("animationend", done);
    el.removeEventListener("animationcancel", done);
  };
});
var Wipe = class extends Component8 {
  static {
    setComponentTemplate8(precompileTemplate8('\n    <div class="cf-swipe" aria-hidden="true" {{retire @seekable}}>\n      <img src={{@still}} alt />\n    </div>\n  ', {
      strictMode: true,
      scope: () => ({
        retire
      })
    }), this);
  }
};
var Melt = class extends Component8 {
  static {
    setComponentTemplate8(precompileTemplate8('\n    <img class="cf-melt" src={{@still}} alt aria-hidden="true" {{retire @seekable}} />\n  ', {
      strictMode: true,
      scope: () => ({
        retire
      })
    }), this);
  }
};
var Blend = class extends Component8 {
  static {
    setComponentTemplate8(precompileTemplate8('\n    <img class="cf-blend" src={{@still}} alt aria-hidden="true" {{retire @seekable}} />\n  ', {
      strictMode: true,
      scope: () => ({
        retire
      })
    }), this);
  }
};
var Iris = class extends Component8 {
  static {
    setComponentTemplate8(precompileTemplate8('\n    <img class="cf-iris" src={{@still}} style={{@at}} alt aria-hidden="true" {{retire @seekable}} />\n  ', {
      strictMode: true,
      scope: () => ({
        retire
      })
    }), this);
  }
};
var Blur = class extends Component8 {
  static {
    setComponentTemplate8(precompileTemplate8('\n    <img class="cf-blurout" src={{@still}} alt aria-hidden="true" {{retire @seekable}} />\n  ', {
      strictMode: true,
      scope: () => ({
        retire
      })
    }), this);
  }
};
var Luma = class extends Component8 {
  static {
    setComponentTemplate8(precompileTemplate8('\n    <img class="cf-luma" src={{@still}} alt aria-hidden="true" {{retire @seekable}} />\n  ', {
      strictMode: true,
      scope: () => ({
        retire
      })
    }), this);
  }
};
var Flash = class extends Component8 {
  static {
    setComponentTemplate8(precompileTemplate8('\n    <i class="cf-flash" aria-hidden="true" {{retire @seekable}}></i>\n  ', {
      strictMode: true,
      scope: () => ({
        retire
      })
    }), this);
  }
};
var Dip = class extends Component8 {
  get veil() {
    return `background:${this.args.color ?? "#0d0905"}`;
  }
  static {
    setComponentTemplate8(precompileTemplate8('\n    <span class="cf-dip" aria-hidden="true" {{retire @seekable}}>\n      {{#if @still}}\n        <img src={{@still}} alt />\n      {{/if}}\n      <i style={{this.veil}}></i>\n    </span>\n  ', {
      strictMode: true,
      scope: () => ({
        retire
      })
    }), this);
  }
};
function seamShape(kind, p) {
  const t = Math.max(0, Math.min(1, p));
  if (kind === "dip") {
    const veil = t < 0.34 ? smoothstep(t / 0.34) : t < 0.44 ? 1 : 1 - smoothstep((t - 0.44) / 0.56);
    return {
      mix: t < 0.4 ? 1 : 0,
      veil
    };
  }
  const e = 1 - (1 - t) * (1 - t);
  return {
    mix: 1 - e,
    veil: 0
  };
}
function inGlass(kind) {
  return kind === "blend" || kind === "melt" || kind === "dip";
}
function smoothstep(x) {
  const t = Math.max(0, Math.min(1, x));
  return t * t * (3 - 2 * t);
}
var PRESENTATIONS = {
  blend: {
    component: Blend,
    secs: 0.52,
    still: true
  },
  blur: {
    component: Blur,
    secs: 0.64,
    still: true
  },
  cut: {
    secs: 0,
    still: false
  },
  defocus: {
    component: Blur,
    secs: 0.7,
    still: true
  },
  dip: {
    component: Dip,
    secs: 0.76,
    still: true
  },
  flash: {
    component: Flash,
    secs: 0.3,
    still: false
  },
  iris: {
    component: Iris,
    secs: 0.9,
    still: true
  },
  luma: {
    component: Luma,
    secs: 0.9,
    still: true
  },
  melt: {
    component: Melt,
    secs: 1.9,
    still: true
  },
  sweep: {
    secs: 0.6,
    still: false
  },
  whip: {
    secs: 0.36,
    still: false
  },
  wipe: {
    component: Wipe,
    secs: 1.15,
    still: true
  }
};
var JOIN_SECS = Object.fromEntries(Object.entries(PRESENTATIONS).map(([k, p]) => [k, p.secs]));
var STILL_JOINS = new Set(Object.entries(PRESENTATIONS).filter(([, p]) => p.still).map(([k]) => k));
var Joins = class extends Component8 {
  get presentation() {
    const p = this.args.kind ? this.args.presentations[this.args.kind] : null;
    if (!p?.component) {
      return void 0;
    }
    if (p.still && !this.args.freeze && this.args.kind !== "dip") {
      return void 0;
    }
    return p.component;
  }
  static {
    setComponentTemplate8(precompileTemplate8('\n    {{#each (array @stamp) key="@identity" as |s|}}\n      {{#if s}}\n        {{#if this.presentation}}\n          <this.presentation @still={{if @freeze @freeze ""}} @at={{@irisAt}} @color={{@dipColor}} @seekable={{@seekable}} />\n        {{/if}}\n      {{/if}}\n    {{/each}}\n  ', {
      strictMode: true,
      scope: () => ({
        array: array2
      })
    }), this);
  }
};
function array2(...items) {
  return items;
}

// dist/film/overlay.js
function mergePatch(a, b) {
  return {
    ...a,
    ...b,
    cam: a.cam || b.cam ? {
      ...a.cam,
      ...b.cam
    } : void 0,
    toCam: a.toCam || b.toCam ? {
      ...a.toCam,
      ...b.toCam
    } : void 0
  };
}
function mergeCam(base, patch) {
  if (!patch) {
    return base;
  }
  if (!base) {
    const dolly = patch.dolly;
    const lookY = patch.lookY;
    const pitch = patch.pitch;
    const yaw = patch.yaw;
    if (dolly === void 0 || lookY === void 0 || pitch === void 0 || yaw === void 0) {
      return void 0;
    }
    return {
      ...patch,
      dolly,
      lookY,
      pitch,
      yaw
    };
  }
  return {
    ...base,
    ...patch
  };
}
function mergeBeat(base, patch) {
  const {
    cam: camPatch,
    toCam: toCamPatch,
    ticks,
    ...rest
  } = patch;
  const next2 = {
    ...base,
    ...rest
  };
  if (camPatch) {
    next2.cam = mergeCam(base.cam, camPatch);
  }
  if (toCamPatch !== void 0) {
    next2.toCam = mergeCam(base.toCam, toCamPatch);
  }
  if (typeof ticks === "number" && Number.isFinite(ticks)) {
    next2.ticks = Math.max(0.25, ticks);
  }
  return next2;
}
function applyOverlay(beats, overlay) {
  if (overlay.size === 0) {
    return beats;
  }
  return beats.map((beat) => {
    const patch = overlay.get(beat.id);
    return patch ? mergeBeat(beat, patch) : beat;
  });
}

// dist/film/overlays.js
import { on } from "@ember/modifier";
import Component9 from "@glimmer/component";
import { precompileTemplate as precompileTemplate9 } from "@ember/template-compilation";
import { setComponentTemplate as setComponentTemplate9 } from "@ember/component";
var Insert2 = class extends Component9 {
  static {
    setComponentTemplate9(precompileTemplate9('\n    <Choreo @id="insert" @releaseOnSeek={{true}} class="cf-photo" as |g|>\n      {{#each (array @beat) key="id" as |b|}}\n        <figure class="is-{{b.mode}}" {{motion id="photo" role="shot"}}>\n          <img src={{@src}} alt {{on "error" @missing}} />\n          <figcaption>\n            <span class="cf-photo-cap">{{b.photo.caption}}</span>\n            <span class="cf-photo-cr">{{b.photo.credit}}</span>\n          </figcaption>\n        </figure>\n      {{/each}}\n      <g.Tween @of={{g.inserted "shot"}} @clipPath={{array "inset(0 100% 0 0)" "inset(0 0% 0 0)"}} @duration={{0.62}} @ease={{array 0.22 1 0.36 1}} />\n      <g.Tween @of={{g.removed "shot"}} @opacity={{0}} @duration={{0.24}} @ease="easeIn" />\n    </Choreo>\n  ', {
      strictMode: true,
      scope: () => ({
        Choreo,
        array: array3,
        motion: MotionModifier,
        on
      })
    }), this);
  }
};
var Captions = class extends Component9 {
  static {
    setComponentTemplate9(precompileTemplate9('\n    {{#if @line}}\n      <p class="cf-subs">{{@line}}</p>\n    {{/if}}\n  ', {
      strictMode: true
    }), this);
  }
};
var Track = class extends Component9 {
  static {
    setComponentTemplate9(precompileTemplate9('\n    <svg class="cf-track" aria-hidden="true" {{@wire}}>\n      <line class="cf-leader" x1="0" y1="0" x2="0" y2="0" />\n      <line class="cf-tether" x1="0" y1="0" x2="0" y2="0" />\n      <circle cx="0" cy="0" r="7" pathLength="1" />\n    </svg>\n  ', {
      strictMode: true
    }), this);
  }
};
var Stamp2 = class extends Component9 {
  static {
    setComponentTemplate9(precompileTemplate9('\n    {{#if @word}}\n      {{#each (array @step) key="@identity"}}\n        <p class="cf-stamp" aria-hidden="true">{{@word}}</p>\n      {{/each}}\n    {{/if}}\n  ', {
      strictMode: true,
      scope: () => ({
        array: array3
      })
    }), this);
  }
};
function array3(...items) {
  return items;
}

// dist/film/plate.js
import { get, concat, array as array4 } from "@ember/helper";
import Component10 from "@glimmer/component";
import { precompileTemplate as precompileTemplate10 } from "@ember/template-compilation";
import { setComponentTemplate as setComponentTemplate10 } from "@ember/component";
var Plate = class extends Component10 {
  static {
    setComponentTemplate10(precompileTemplate10('\n    <Choreo @id="plate" @releaseOnSeek={{true}} class="cf-type cf-{{@beat.mode}}" as |n|>\n      <span class="cf-ghost" aria-hidden="true">{{@chapterN}}</span>\n      {{#if @rolling}}\n        {{#each (array @beat) key="id" as |b|}}\n          <div class="cf-block is-{{b.mode}}" {{@mount}}>\n            {{#if b.kicker}}\n              <div class="cf-plane">\n                <p class="cf-kicker" {{motion id="kicker" role="kick"}}>\n                  <span>{{b.kicker}}</span>\n                </p>\n              </div>\n            {{/if}}\n            {{!-- when the beat has a MARK the term is already standing in\n            the scene, so the front layer does not set it a second time --}}\n            {{#unless b.mark}}\n              {{#if b.kanji}}\n                <div class="cf-plane is-glyph" style={{@glyphFit}}>\n                  <p class="cf-kanji {{@glyphTone}}" {{motion id="kanji" role="glyph"}}>\n                    {{b.kanji}}\n                  </p>\n                </div>\n              {{/if}}\n            {{/unless}}\n            {{#if b.romaji}}\n              <div class="cf-plane">\n                <p class="cf-read" {{motion id="read" role="read"}}>\n                  <span class="cf-romaji">{{b.romaji}}</span>\n                  {{#if b.gloss}}\n                    <span class="cf-gloss">{{b.gloss}}</span>\n                  {{/if}}\n                </p>\n              </div>\n            {{/if}}\n            {{!-- kinetic type, not a paragraph: each phrase is its own sprite\n            with its own role, because a cue has a time --}}\n            {{#each b.says as |say index|}}\n              <div class="cf-plane">\n                <p class="cf-say" {{motion id=(concat "say" index) role=(concat "s" index)}}><span class="cf-sayx sx-{{b.id}}-{{index}}">{{say}}</span></p>\n              </div>\n            {{/each}}\n          </div>\n        {{/each}}\n      {{/if}}\n\n      {{!-- THE TYPE IS ITS OWN SCENE. Every element enters and leaves on one\n      vocabulary and in one order: kicker, glyph, reading, then the lines\n      against the voice; out as a wave in reverse. --}}\n      <n.Parallel>\n        <n.Tween @of={{n.inserted "kick"}} @delay={{get @typeAt 0}} @opacity={{array 0 1}} @y={{array 10 0}} @duration={{0.55}} @ease="easeOut" />\n        <n.Tween @of={{n.inserted "glyph"}} @by="character" @order="center" @stagger={{0.07}} @delay={{get @typeAt 1}} @opacity={{array 0 1}} @y={{array 16 0}} @duration={{0.9}} @ease="easeOut" />\n        <n.Tween @of={{n.inserted "read"}} @delay={{get @typeAt 2}} @opacity={{array 0 1}} @y={{array 8 0}} @duration={{0.62}} @ease="easeOut" />\n        <n.Tween @of={{n.inserted "s0"}} @delay={{get @sayAt 0}} @opacity={{array 0 1}} @y={{array 8 0}} @duration={{0.7}} @ease="easeOut" />\n        <n.Tween @of={{n.inserted "s1"}} @delay={{get @sayAt 1}} @opacity={{array 0 1}} @y={{array 8 0}} @duration={{0.7}} @ease="easeOut" />\n        <n.Tween @of={{n.inserted "s2"}} @delay={{get @sayAt 2}} @opacity={{array 0 1}} @y={{array 8 0}} @duration={{0.7}} @ease="easeOut" />\n        <n.Tween @of={{n.inserted "s3"}} @delay={{get @sayAt 3}} @opacity={{array 0 1}} @y={{array 8 0}} @duration={{0.7}} @ease="easeOut" />\n        <n.Tween @of={{array (n.removed "s0") (n.removed "s1") (n.removed "s2") (n.removed "s3")}} @opacity={{0}} @y={{array 0 -7}} @duration={{0.3}} @ease="easeIn" />\n        <n.Tween @of={{n.removed "read"}} @delay={{0.05}} @opacity={{0}} @y={{array 0 -7}} @duration={{0.3}} @ease="easeIn" />\n        <n.Tween @of={{n.removed "glyph"}} @delay={{0.1}} @opacity={{0}} @y={{array 0 -9}} @duration={{0.34}} @ease="easeIn" />\n        <n.Tween @of={{n.removed "kick"}} @delay={{0.16}} @opacity={{0}} @y={{array 0 -7}} @duration={{0.3}} @ease="easeIn" />\n      </n.Parallel>\n    </Choreo>\n  ', {
      strictMode: true,
      scope: () => ({
        Choreo,
        array: array4,
        motion: MotionModifier,
        concat,
        get
      })
    }), this);
  }
};

// dist/film/player.js
import { fn } from "@ember/helper";
import { on as on2 } from "@ember/modifier";
import Component11 from "@glimmer/component";
import { precompileTemplate as precompileTemplate11 } from "@ember/template-compilation";
import { setComponentTemplate as setComponentTemplate11 } from "@ember/component";
var Player = class extends Component11 {
  static {
    setComponentTemplate11(precompileTemplate11(`
    <div class="cf-player {{if @idle "is-idle"}} {{if @away "is-away"}}">
      <div class="cf-scrub {{if @scrubAt "is-live"}}" role="slider" aria-label="playhead" aria-valuemin="0" aria-valuemax="100" aria-valuenow="0" tabindex="0" {{@slider}} {{on "pointerdown" @scrubDown}} {{on "pointermove" @scrubMove}} {{on "pointerup" @scrubUp}} {{on "pointerleave" @scrubLeave}}>
        <span class="cf-scrub-track" {{@trackWrap}}>
          {{#each @playbar as |c|}}
            <span class="cf-scrub-ch" style={{c.style}}>
              <em></em>
              <i></i>
            </span>
          {{/each}}
          <span class="cf-scrub-head"></span>
          {{#if @tip}}
            <span class="cf-scrub-tip">
              <small>{{@tip.ch}}</small>
              <b>{{@tip.t}}</b>
            </span>
          {{/if}}
        </span>
      </div>

      <div class="cf-controls">
        <button type="button" class="cf-ic" aria-label={{if @live "pause" "play"}} data-tip={{if @live "Pause (k)" "Play (k)"}} {{on "click" @toggle}}>
          {{#if @live}}
            <svg viewBox="0 0 24 24"><path d="M7 5h4v14H7zM13 5h4v14h-4z" /></svg>
          {{else}}
            <svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z" /></svg>
          {{/if}}
        </button>
        <button type="button" class="cf-ic" aria-label="previous chapter" data-tip="Previous chapter (\u2190)" {{on "click" @prev}}>
          <svg viewBox="0 0 24 24"><path d="M6 6h2v12H6zM18 6l-9 6 9 6z" /></svg>
        </button>
        <button type="button" class="cf-ic" aria-label="next chapter" data-tip="Next chapter (\u2192)" {{on "click" @next}}>
          <svg viewBox="0 0 24 24"><path d="M16 6h2v12h-2zM6 6l9 6-9 6z" /></svg>
        </button>
        {{!-- the speaker and, on a hover, the fader beside it --}}
        <span class="cf-vol">
          <button type="button" class="cf-ic" aria-label={{if @sound "mute" "sound"}} data-tip={{if @sound "Mute (m)" "Unmute (m)"}} {{on "click" @hear}}>
            {{#if (eq @loud "high")}}
              <svg viewBox="0 0 24 24"><path d="M4 9v6h4l5 4V5L8 9zm11.5 3a3.5 3.5 0 0 0-2-3.2v6.4a3.5 3.5 0 0 0 2-3.2zm-2-7.6v2.1a5.6 5.6 0 0 1 0 11v2.1a7.7 7.7 0 0 0 0-15.2z" /></svg>
            {{else if (eq @loud "low")}}
              <svg viewBox="0 0 24 24"><path d="M4 9v6h4l5 4V5L8 9zm11.5 3a3.5 3.5 0 0 0-2-3.2v6.4a3.5 3.5 0 0 0 2-3.2z" /></svg>
            {{else}}
              <svg viewBox="0 0 24 24"><path d="M4 9v6h4l5 4V5L8 9zm12.6 3 2.7-2.7-1.4-1.4-2.7 2.7-2.7-2.7-1.4 1.4 2.7 2.7-2.7 2.7 1.4 1.4 2.7-2.7 2.7 2.7 1.4-1.4z" /></svg>
            {{/if}}
          </button>
          <input class="cf-vol-range" type="range" min="0" max="1" step="0.02" value={{@vol}} aria-label="volume" style={{@volStyle}} {{on "input" @fade}} />
        </span>
        <span class="cf-time">
          <b>{{@clock}}</b>
          <i>/</i>
          {{@duration}}
        </span>
        {{!-- the chapter's name, beside the clock, is the way into the list --}}
        <button type="button" class="cf-chap" data-tip="Chapters (c)" {{on "click" @toc}}>
          <span>\xB7</span>
          {{@chapter.n}}
          {{@chapter.title}}
          <svg viewBox="0 0 24 24"><path d="M8.6 6 7.2 7.4 11.8 12l-4.6 4.6L8.6 18l6-6z" /></svg>
        </button>
        <span class="cf-spacer"></span>
        {{#if @debug}}
          <span class="cf-build">{{@build}}</span>
        {{/if}}
        <button type="button" class="cf-ic cf-ic-cc {{if @subsOn "is-on"}}" aria-label="captions" data-tip="Captions (v)" {{on "click" @cc}}>CC</button>
        {{!-- the way back to the door, with its name on it: a title screen
        is a place, not a loop --}}
        <button type="button" class="cf-word" data-tip="Back to the title screen (0)" {{on "click" @restart}}>
          {{!-- a title card, not a loop: the glyph is the card itself --}}
          <svg viewBox="0 0 24 24"><path d="M3 5h18v14H3zm2 2v10h14V7zm3 3h8v1.6H8zm0 3.4h5V15H8z" /></svg>
          Title screen
        </button>
        <button type="button" class="cf-ic cf-ic-last" aria-label={{if @full "exit fullscreen" "fullscreen"}} data-tip={{if @full "Exit full screen (f)" "Full screen (f)"}} {{on "click" @screen}}>
          {{#if @full}}
            <svg viewBox="0 0 24 24"><path d="M9 4H7v3H4v2h5zM4 15h3v3h2v-5H4zm11 3h2v-3h3v-2h-5zm0-14v5h5V7h-3V4z" /></svg>
          {{else}}
            <svg viewBox="0 0 24 24"><path d="M4 4h5v2H6v3H4zm11 0h5v5h-2V6h-3zM4 15h2v3h3v2H4zm14 0h2v5h-5v-2h3z" /></svg>
          {{/if}}
        </button>
      </div>
    </div>
  `, {
      strictMode: true,
      scope: () => ({
        on: on2,
        eq: eq2
      })
    }), this);
  }
};
var Burst = class extends Component11 {
  static {
    setComponentTemplate11(precompileTemplate11('\n    <div class="cf-burst" {{on "animationend" @done}}>\n      {{#if (eq @kind "play")}}\n        <svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z" /></svg>\n      {{else}}\n        <svg viewBox="0 0 24 24"><path d="M7 5h4v14H7zM13 5h4v14h-4z" /></svg>\n      {{/if}}\n    </div>\n  ', {
      strictMode: true,
      scope: () => ({
        on: on2,
        eq: eq2
      })
    }), this);
  }
};
var Menu = class extends Component11 {
  static {
    setComponentTemplate11(precompileTemplate11('\n    <Choreo class="cf-menu" as |m|>\n      <div class="cf-menu-in" {{motion id="menu" role="sheet"}}>\n        <p class="cf-menu-head">{{@title}}</p>\n        <p class="cf-menu-sub">{{@sub}}</p>\n        <ol class="cf-menu-list">\n          {{#each @contents as |c|}}\n            <li>\n              <button type="button" class="cf-menu-item {{if c.here "is-here"}}" {{on "click" (fn @pick c.head)}}>\n                <span class="cf-menu-n">{{c.n}}</span>\n                <span class="cf-menu-t">{{c.title}}</span>\n                <span class="cf-menu-d">{{c.shots}} shots</span>\n              </button>\n            </li>\n          {{/each}}\n        </ol>\n        <p class="cf-menu-keys">{{if @keys @keys "space / K play \xB7 \u2190 \u2192 chapter \xB7 1\u20139 chapter \xB7 M sound \xB7 F full screen \xB7 V captions \xB7 0 title screen \xB7 C close"}}</p>\n      </div>\n      <m.Tween @of={{m.inserted "sheet"}} @y={{array 26 0}} @scale={{array 0.97 1}} @opacity={{array 0 1}} @duration={{0.42}} @ease={{array 0.22 1 0.36 1}} />\n      <m.Tween @of={{m.removed "sheet"}} @y={{array 0 18}} @opacity={{array 1 0}} @duration={{0.2}} @ease="easeIn" />\n    </Choreo>\n  ', {
      strictMode: true,
      scope: () => ({
        Choreo,
        motion: MotionModifier,
        on: on2,
        fn,
        array: array5
      })
    }), this);
  }
};
function array5(...items) {
  return items;
}
function eq2(a, b) {
  return a === b;
}

// dist/film/rail.js
import { fn as fn2 } from "@ember/helper";
import { on as on3 } from "@ember/modifier";
import Component12 from "@glimmer/component";
import { precompileTemplate as precompileTemplate12 } from "@ember/template-compilation";
import { setComponentTemplate as setComponentTemplate12 } from "@ember/component";
var Rail = class extends Component12 {
  atStyle = (m) => `left:calc(5px + ${m.at.toFixed(4)} * (100% - 10px))`;
  static {
    setComponentTemplate12(precompileTemplate12('\n    <div class="cf-rail">\n      <span class="cf-rail-n">{{@chapter.n}}</span>\n      <span class="cf-rail-t">{{@chapter.title}}</span>\n      <span class="cf-years">\n        <i class="cf-years-rule" aria-hidden="true"></i>\n        <i class="cf-years-fill" aria-hidden="true"></i>\n        {{#each @marks as |m|}}\n          <button type="button" class="cf-years-ch {{if m.here "is-here"}} {{if m.done "is-done"}}" style={{this.atStyle m}} title="{{m.n}} {{m.title}}{{if m.label (concat " \xB7 " m.label)}}" {{on "click" (fn @pick m.head)}}></button>\n        {{/each}}\n        {{#if @readout}}\n          <b class="cf-years-now" aria-hidden="true">{{@readout}}</b>\n        {{else}}\n          <b class="cf-years-now is-mute" aria-hidden="true"></b>\n        {{/if}}\n        {{#if @labels}}\n          <em class="cf-years-a" aria-hidden="true">{{get @labels 0}}</em>\n          <em class="cf-years-b" aria-hidden="true">{{get @labels 1}}</em>\n        {{/if}}\n      </span>\n    </div>\n  ', {
      strictMode: true,
      scope: () => ({
        concat: concat2,
        on: on3,
        fn: fn2,
        get: get2
      })
    }), this);
  }
};
function concat2(...parts) {
  return parts.map((p) => String(p ?? "")).join("");
}
function get2(list, i) {
  return list[i];
}

// dist/film/seam.js
var Seam = class {
  /** which cut is in hand; a later one retires an earlier one */
  turn = 0;
  /**
   * Hold `cut` until `still` can be painted, or run it now if there is
   * no still. `cap` is the longest the film will wait on a decode.
   */
  hold(still, cut, cap = 120) {
    if (!still) {
      cut();
      return;
    }
    const mine = this.turn += 1;
    let ran = false;
    const go = () => {
      if (ran || mine !== this.turn) {
        return;
      }
      ran = true;
      cut();
    };
    const pre = new Image();
    pre.src = still;
    setTimeout(go, cap);
    const decoding = pre.decode?.();
    if (decoding) {
      void decoding.then(go, go);
    } else {
      go();
    }
  }
};

// dist/film/shot-math.js
var flownOf = (since, secs) => Math.min(1, Math.max(0, since / secs));
function bob(flown, dolly, amount = 0.5) {
  const air = amount / Math.max(0.8, Math.min(3, dolly));
  return air * Math.sin(flown * Math.PI * 1.6) * smooth(Math.min(1, flown / 0.18)) * smooth(Math.min(1, (1 - flown) / 0.18));
}
var HAND = 0.17;
var wander = (clock, a, b, c) => Math.sin(clock * a) * 0.6 + Math.sin(clock * b) * 0.3 + Math.sin(clock * c) * 0.1;
function hand(clock, dolly, amp = HAND) {
  const h = amp / Math.max(0.8, Math.min(3.4, dolly));
  return {
    az: h * 0.25 * wander(clock, 0.37, 0.93, 2.11),
    el: h * 1.2 * wander(clock, 0.29, 1.07, 1.83),
    zoom: 1 + 11e-4 * (amp / HAND) * wander(clock, 0.23, 0.71, 1.51)
  };
}
function typeA(e) {
  const left = Math.max(0, e.span - e.since);
  const wait = e.typeAt - 0.05;
  const enter = smooth(Math.max(0, Math.min(1, (e.since - wait) / 0.4)));
  const tailA = e.ended ? 0 : e.last ? smooth(Math.max(0, Math.min(1, (left - e.endOff - 0.5) / 2))) : smooth(Math.min(1, left / 1));
  return Math.min(enter, tailA, e.reveal);
}
var titleK = (title, since, span) => title ? smooth(Math.max(0, Math.min(1, (since - 1) / Math.max(0.5, span - 1.4)))) : 1;
function stampAt(local, secs, read, typeAt, at2 = 0.06) {
  const t0 = (read * at2 + typeAt) / secs;
  const rise = 0.9 / secs;
  const hold = 2.6 / secs;
  const fall = 1.1 / secs;
  const inK = Math.max(0, Math.min(1, (local - t0) / rise));
  const outK = Math.max(0, Math.min(1, (local - t0 - rise - hold) / fall));
  return smooth(inK) * (1 - smooth(outK));
}
var ghostA = (local, tail, stamp) => (tail ? 1 - smooth(Math.max(0, (local - 0.72) / 0.22)) : 1) * (1 - stamp);
var skyIn = (since) => smooth(Math.min(1, since / 0.62));
var skyOpacity = (on5, local, strength = 0.4) => on5 * strength * 0.78 * smooth(Math.max(0, Math.min(1, (local - 0.16) / 0.16))) * (1 - smooth(Math.max(0, Math.min(1, (local - 0.52) / 0.16))));
var markOpacity = (local, at2 = 0.14, hold = 0.34) => 0.62 * smooth(Math.max(0, Math.min(1, (local - at2) / 0.16))) * (1 - smooth(Math.max(0, Math.min(1, (local - (at2 + hold)) / 0.2))));
var traceGone = (local) => Math.min(1, Math.max(0, (local - 0.78) / 0.16));
var traceDraw = (since, i) => Math.min(1, Math.max(0, (since - 0.04 - i * 0.12) / 0.16));
var traceUndraw = (gone, i) => Math.min(1, Math.max(0, gone * (1 + i * 0.25)));
var calloutDraw = (since) => Math.min(1, Math.max(0, (since - 0.04) / 0.18));
function cloud(local, index, secs) {
  if (secs < 8) {
    return null;
  }
  const phase = index * 0.37 % 1 * 0.25;
  const w = Math.max(0, Math.min(1, (local - 0.12 - phase) / 0.62));
  return Math.sin(Math.PI * w) ** 2;
}

// dist/film/styles.js
import Component13 from "@glimmer/component";
import { precompileTemplate as precompileTemplate13 } from "@ember/template-compilation";
import { setComponentTemplate as setComponentTemplate13 } from "@ember/component";
var FilmStyles = class extends Component13 {
  static {
    setComponentTemplate13(precompileTemplate13(`
    <style>
      /* THE FLAG, as an accent system. Two colours and nothing else:
         the red of the hinomaru for the one thing that is happening NOW
         \u2014 the playhead, the current chapter, the seal, the point a line
         is drawn to \u2014 and a full white for type that has to win over a
         picture. Everything else stays in the scene's own inks, so the
         red never becomes decoration; it only ever means "here". */
      .cf-page {
        --cf-red: #bc002d;
        --cf-white: #fffdf8;
      }

      .cf-page {
        /* the film's ink, replaced per chapter from the scene's own
           time-of-day palette by wear \u2014 these are the morning values,
           which is also what the page opens on. --cf-shx/y is the cast
           shadow's offset, written every frame from where the scene's key
           light actually is (see follow). */
        --cf-paper: #ecdcbc;
        --cf-paper-a: rgba(236, 220, 188, 0.94);
        --cf-paper-b: rgba(236, 220, 188, 0.76);
        --cf-paper-c: rgba(236, 220, 188, 0);
        --cf-ink: #2e2515;
        --cf-ink2: #8b7c5c;
        --cf-ink3: #3f3520;
        --cf-accent: #a8621f;
        /* THE ANNOTATION RED, and it is a different colour from the
           editorial accent on purpose. The accent is ink \u2014 it belongs to
           the page and takes the page's palette. This is a marker: it is
           not in the scene, it never was, and it should look like
           somebody drew on the photograph. Muted burnt orange over ochre
           moss reads as part of the picture, which is exactly what an
           annotation must not do. */
        --cf-mark: #ff2412;
        --cf-rule: #c2b18c;
        /* The sun, in two numbers: cf-rake is the angle its light makes
           across the frame, cf-shx/cf-shy the direction away from it.
           They dress the things that are PHYSICALLY on the frame \u2014 the
           photograph's own plate, the rake of a rule \u2014 and deliberately
           not the type. An offset shadow behind a headline is a sticker
           effect: it claims the letters are objects lying on the picture,
           which they are not, and getting the angle right does not rescue
           it. Type here earns its contrast from the scrim. */
        /* TYPE. The display face is a serif on purpose. This film is set
           beside mincho kanji and stands in front of a building, and a
           wide-tracked geometric sans fights both \u2014 it is also the first
           thing every deck reaches for, which is reason enough to leave
           it alone. A warm old-style serif sits with the kanji instead of
           arguing with it. The sans is kept for small mechanical labels
           only, and its tracking is pulled well back from the point where
           letterspaced caps start reading as a logo. */
        /* THE INFORMATION LAYER IS SET IN THE BASILICA'S OWN VOICE.
           The 2026 centenary identity is heavy grotesque capitals in flat
           colour on stone paper \u2014 the programme, the plates, the timeline
           of momentums are all cut that way, and a film about the same
           building in the same year has no business inventing a second
           typography for the same facts. Archivo is the closest open face
           to it: a grotesque with real weight at 800 and none of the
           geometric-sans blandness. The old-style serif stays for the
           quote and the caption band, where a sentence is being spoken
           rather than displayed. */
        --cf-display: Archivo, 'Helvetica Neue', Helvetica, Arial, sans-serif;
        --cf-caps: Archivo, 'Helvetica Neue', Helvetica, Arial, sans-serif;
        --cf-serif:
          'Cormorant Garamond', 'Iowan Old Style', 'Palatino Linotype',
          Palatino, Georgia, serif;
        --cf-ui: Archivo, 'Helvetica Neue', Helvetica, Arial, sans-serif;
        /* the identity's four colours, and the chapter's own (set by wear) */
        --cf-c-red: #d8232a;
        --cf-c-blue: #1268c3;
        --cf-c-green: #0f7b62;
        --cf-c-pink: #e5308a;
        --cf-chap: #d8232a;
        --cf-shx: 2px;
        --cf-shy: 2px;
        --cf-rake: 35deg;

        position: relative;
        min-height: 100svh;
        background: var(--cf-paper);
        display: flex;
        flex-direction: column;
        transition: background 900ms ease;
      }

      .cf-stage {
        position: relative;
        height: 100svh;
        flex: none;
        overflow: hidden;
      }

      /* CONTAINED: the box is the viewport. The page fills its parent, and
         everything that was fixed to the window is placed in the page \u2014
         the page is its containing block (a transform makes it one for
         anything still fixed). */
      .cf-page.is-contained {
        min-height: 0;
        height: 100%;
        overflow: hidden;
        transform: translateZ(0);
      }
      .cf-page.is-contained .cf-stage,
      .cf-page.is-contained .cf-menu {
        height: 100%;
      }
      .cf-page.is-contained .cf-player,
      .cf-page.is-contained .cf-burst {
        position: absolute;
      }

      .cf-live {
        position: absolute;
        inset: 0;
      }

      /* THE SCENE DOES NOT TAKE THE POINTER. It is a picture: it has no
         controls of its own in film mode, and while it swallowed events
         the wheel went to the iframe's document instead of this page \u2014
         so the film filled the viewport and the wall plate underneath
         could not be reached. */
      .cf-frame {
        pointer-events: none;
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
        border: 0;
        display: block;
        /* the primary: contrast, saturation and lift, per grade */
      }

      /* ---- the grade ------------------------------------------------- *
         Two passes, the way a colourist works: a primary on the picture
         itself (above), then a split tone laid over it \u2014 warmth into the
         highlights on one diagonal, coolness into the shadows on the
         other. Soft-light rather than overlay, because overlay crushes this scene's
         mid-tones and the whole point is to keep the moss and the plaster
         legible while moving the mood underneath them.
         ---------------------------------------------------------------- */

      /* the five moods. CONTEXT opens warm and open; HISTORY is archival \u2014
         desaturated, cool, contrastier, the look of a document rather than
         a day; CONSTRUCTION goes clean and bright, nearly a blueprint;
         DETAIL is rich and close; COMPARISON is a museum plate, flat and
         even, because a comparison that flatters one subject is not one. */
      .is-grade-amber {
        --cf-lut: saturate(0.9) contrast(0.94) brightness(1.2);
        --cf-warm: #ffd9a8;
        --cf-cool: #b9c8e6;
        --cf-grade-a: 0.3;
        --cf-vig-a: 0.5;
      }

      .is-grade-iron {
        --cf-lut: saturate(0.72) contrast(0.98) brightness(1.12) sepia(0.1);
        --cf-warm: #e8d9c2;
        --cf-cool: #9fb0c8;
        --cf-grade-a: 0.4;
        --cf-vig-a: 0.65;
      }

      /* MIDDAY, and it is meant to be the brightest thing in the film.
         The construction chapter is the one that has to read as
         information \u2014 you are watching a building get assembled \u2014 so it
         is pushed up and opened out until it is nearly a working
         drawing, and it earns its brightness by sitting between two
         chapters that are deliberately heavier. Contrast between
         chapters is a bigger effect than contrast inside one. */
      .is-grade-chalk {
        --cf-lut: saturate(0.88) contrast(0.96) brightness(1.34);
        --cf-warm: #fffdf6;
        --cf-cool: #cfdde8;
        --cf-grade-a: 0.2;
        --cf-vig-a: 0.22;
      }

      .is-grade-ink {
        --cf-lut: saturate(0.98) contrast(1) brightness(1.16);
        --cf-warm: #ffc9a1;
        --cf-cool: #8fa0c9;
        --cf-grade-a: 0.32;
        --cf-vig-a: 0.68;
      }

      /* THE NIGHT: the one grade that pulls the picture DOWN. Every other
         grade lifts, which is right for daylight; a lifted night is dusk. */
      .is-grade-night {
        --cf-lut: saturate(0.76) contrast(1.14) brightness(0.76);
        --cf-warm: #c9c2b4;
        --cf-cool: #8193b8;
        --cf-grade-a: 0.5;
        --cf-vig-a: 0;
      }

      /* WET. Rain is not simply the clear grade with drops in it: the
         light comes from a lid rather than a source, so the picture
         loses its warmth and most of its contrast, and the corners
         close in. */
      .is-grade-wet {
        --cf-lut: saturate(0.72) contrast(0.92) brightness(0.94)
          hue-rotate(-4deg);
        --cf-warm: #cfd6dd;
        --cf-cool: #7d8b9e;
        --cf-grade-a: 0.44;
        --cf-vig-a: 0.8;
      }

      .is-grade-plate {
        --cf-lut: saturate(0.86) contrast(0.95) brightness(1.2);
        --cf-warm: #f6e8d2;
        --cf-cool: #c3c8bd;
        --cf-grade-a: 0.18;
        --cf-vig-a: 0.36;
      }

      /* SIX COUNTRIES, SIX LIGHTS. The comparison holds the framing and
         the lens still so the BUILDING is the variable \u2014 but six towers
         under one identical sky read as six models on one lawn, which
         is a diorama, not a comparison. Each gets the tone its own
         country is remembered in, at a strength you feel and cannot
         quite name: the plate grade, bent a few degrees. */
      .is-grade-c-jp {
        --cf-lut: saturate(0.84) contrast(0.95) brightness(1.22);
        --cf-warm: #f6e8d2;
        --cf-cool: #bcc6bb;
        --cf-grade-a: 0.2;
        --cf-vig-a: 0.36;
      }

      .is-grade-c-cn {
        --cf-lut: saturate(0.95) contrast(0.97) brightness(1.16) sepia(0.06);
        --cf-warm: #ffd9a0;
        --cf-cool: #c0a68e;
        --cf-grade-a: 0.28;
        --cf-vig-a: 0.44;
      }

      .is-grade-c-vn {
        --cf-lut: saturate(0.92) contrast(0.94) brightness(1.18)
          hue-rotate(-6deg);
        --cf-warm: #eef0cd;
        --cf-cool: #a7bda8;
        --cf-grade-a: 0.26;
        --cf-vig-a: 0.4;
      }

      .is-grade-c-th {
        --cf-lut: saturate(1.02) contrast(0.93) brightness(1.3);
        --cf-warm: #ffe9ad;
        --cf-cool: #d3c6a0;
        --cf-grade-a: 0.24;
        --cf-vig-a: 0.3;
      }

      .is-grade-c-kh {
        --cf-lut: saturate(0.9) contrast(0.99) brightness(1.14) sepia(0.12);
        --cf-warm: #f2cfa4;
        --cf-cool: #b9a184;
        --cf-grade-a: 0.3;
        --cf-vig-a: 0.5;
      }

      .is-grade-c-tr {
        --cf-lut: saturate(0.8) contrast(0.96) brightness(1.26);
        --cf-warm: #fdf3e2;
        --cf-cool: #a9bacd;
        --cf-grade-a: 0.22;
        --cf-vig-a: 0.34;
      }

      /* the outgoing frame, swept off along the sun's diagonal behind a
         FEATHERED edge \u2014 a mask, not a clip, because a wipe with a hard
         edge is a screen transition and a wipe with a soft one is film */
      /* THE SWEEP IS TWO TRANSFORMS, NOT A MASK MOVING. Sliding
         mask-position repaints a full-resolution still every frame and
         the wipe stutters \u2014 which is what a wipe must never do. So the
         mask stays put on a sheet three frames wide, the SHEET slides
         across the picture, and the still inside slides back by the same
         amount so it never moves on screen. Both are transforms: the
         compositor rasterises the masked sheet once and only translates. */
      /**
       * THE WIPE, AS A MOVING EDGE RATHER THAN A MOVING BOX.
       *
       * It used to be a box three frames wide carrying the gradient, with
       * the image inside counter-moving so the edge appeared to cross. The
       * travel was hardcoded up-left while the gradient's angle followed
       * the SUN, so the two agreed only by luck: projected, the sweep was
       * 0.92 of its intended distance at one rake, 0.16 at another, 0 at
       * -27 degrees, and NEGATIVE past 0 \u2014 where the edge ran backwards
       * and the outgoing frame grew back over the incoming one. Sizing the
       * travel to the angle fixed the projection but not the geometry:
       * WHICH corner of the box the still starts at also depends on the
       * angle's quadrant, so at some rakes it began already uncovered.
       *
       * So nothing moves now. The element is the frame, the still fills
       * it, and the two gradient stops are swept from before the frame to
       * past it by one number. At p = 0 both stops are behind the frame,
       * so it is wholly opaque; at p = 1 both are past it, so it is wholly
       * gone. That is true at every angle, which the old one never was.
       */
      @property --cf-wipe-p {
        syntax: '<number>';
        initial-value: 0;
        inherits: false;
      }

      .cf-swipe {
        position: absolute;
        inset: 0;
        z-index: 0;
        pointer-events: none;
        will-change: mask-position, opacity;
        /* the band is 24% of the gradient's line: soft enough to read as
           a feathered edge, tight enough to read as an edge */
        --cf-wipe-a: calc(var(--cf-wipe-p) * 150% - 45%);
        mask-image: linear-gradient(
          calc(var(--cf-rake, 35deg) + 72deg),
          transparent var(--cf-wipe-a),
          #000 calc(var(--cf-wipe-a) + 24%)
        );
        -webkit-mask-image: linear-gradient(
          calc(var(--cf-rake, 35deg) + 72deg),
          transparent var(--cf-wipe-a),
          #000 calc(var(--cf-wipe-a) + 24%)
        );
        /* Star Wars speed: a wipe is a STATEMENT, and at two-thirds of a
           second it reads as a glitch rather than a decision */
        animation: cf-swipe 1150ms cubic-bezier(0.42, 0, 0.28, 1) forwards;
      }

      .cf-swipe img {
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }

      @keyframes cf-swipe {
        0% {
          --cf-wipe-p: 0;
          opacity: 1;
        }

        88% {
          opacity: 1;
        }

        100% {
          --cf-wipe-p: 1;
          opacity: 0;
        }
      }

      .cf-melt {
        position: absolute;
        inset: 0;
        z-index: 0;
        width: 100%;
        height: 100%;
        object-fit: cover;
        pointer-events: none;
        animation: cf-melt 1900ms cubic-bezier(0.4, 0, 0.5, 1) forwards;
      }

      @keyframes cf-melt {
        0% {
          opacity: 1;
        }

        22% {
          opacity: 0.92;
        }

        100% {
          opacity: 0;
        }
      }

      .cf-blend {
        position: absolute;
        inset: 0;
        z-index: 0;
        width: 100%;
        height: 100%;
        object-fit: cover;
        pointer-events: none;
        /* the still wears the same primary as the live frame under it,
           so the dissolve is between two graded pictures \u2014 and it is a
           PUSH dissolve: the old frame travels gently forward as it
           thins, so the transition has a direction, not just a mix */
        animation: cf-blend 520ms ease-out forwards;
      }

      @keyframes cf-blend {
        0% {
          opacity: 1;
          transform: scale(1);
        }

        100% {
          opacity: 0;
          transform: scale(1.055);
        }
      }

      /* the blur dissolve \u2014 and the freeze half of the rack-defocus */
      .cf-blurout {
        position: absolute;
        inset: 0;
        z-index: 0;
        width: 100%;
        height: 100%;
        object-fit: cover;
        pointer-events: none;
        animation: cf-blurout 640ms ease-out forwards;
      }

      @keyframes cf-blurout {
        0% {
          opacity: 1;
          filter: blur(0);
        }

        100% {
          opacity: 0;
          filter: blur(13px);
        }
      }

      /* the optical dissolve: lighten blend, so highlights linger */
      .cf-luma {
        position: absolute;
        inset: 0;
        z-index: 0;
        width: 100%;
        height: 100%;
        object-fit: cover;
        pointer-events: none;
        mix-blend-mode: lighten;
        animation: cf-blend 700ms ease-in forwards;
      }

      /* two breaths of white, no freeze \u2014 the gun-crack */
      .cf-flash {
        position: absolute;
        inset: 0;
        z-index: 4;
        pointer-events: none;
        background: #fff8ec;
        animation: cf-flash 300ms ease-out forwards;
      }

      @keyframes cf-flash {
        0%,
        22% {
          opacity: 0.92;
        }

        100% {
          opacity: 0;
        }
      }

      /* the old shot closes in a circle onto the new shot's subject */
      .cf-iris {
        position: absolute;
        inset: 0;
        z-index: 0;
        width: 100%;
        height: 100%;
        object-fit: cover;
        pointer-events: none;
        clip-path: circle(150% at var(--ix, 50%) var(--iy, 50%));
        animation: cf-iris 680ms cubic-bezier(0.45, 0, 0.3, 1) forwards;
      }

      @keyframes cf-iris {
        0% {
          clip-path: circle(150% at var(--ix, 50%) var(--iy, 50%));
          opacity: 1;
        }

        92% {
          opacity: 1;
        }

        100% {
          clip-path: circle(0% at var(--ix, 50%) var(--iy, 50%));
          opacity: 0;
        }
      }

      .cf-dip {
        position: absolute;
        inset: 0;
        z-index: 0;
        pointer-events: none;
      }

      .cf-dip img {
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
        object-fit: cover;
        animation: cf-dip-frame 760ms linear forwards;
      }

      /* the freeze holds until the veil has fully closed, then drops
         under cover \u2014 the incoming shot is never seen before the dip */
      /* the outgoing frame is swapped for the incoming one IN THE DARK,
         inside the veil's hold, so none of the change is ever on screen */
      @keyframes cf-dip-frame {
        0%,
        37% {
          opacity: 1;
        }

        41%,
        100% {
          opacity: 0;
        }
      }

      .cf-dip i {
        position: absolute;
        inset: 0;
        opacity: 0;
        /* linear: the curve is in the stops, and it is not an ease */
        animation: cf-dip-veil 760ms linear forwards;
      }

      /**
       * A DIP CLOSES A SHUTTER; IT DOES NOT RAISE A BLIND.
       *
       * The veil is composited in sRGB, so an opacity of a leaves
       * (1 - a)^2.2 of the LIGHT: a veil eased evenly to black is down to
       * a fifth of the light by the halfway mark and then crawls, which is
       * why the dip read as a lurch and then a wait rather than a fade.
       * What a shutter does is take the LIGHT down smoothly, and the alpha
       * that produces a smooth fall in light is this \u2014 nearly nothing for
       * the first third, then a rush into black. The stops carry the
       * curve, so the timing function is linear.
       *
       * Close over 34%, hold black for 10% (a dip is punctuation and the
       * hold is the full stop), open over the remaining 56%: the way out
       * is longer than the way in, which is the editor's convention and
       * the reason a dip lands rather than bounces.
       */
      @keyframes cf-dip-veil {
        0% {
          opacity: 0;
        }

        6.8% {
          opacity: 0.049;
        }

        13.6% {
          opacity: 0.178;
        }

        17% {
          opacity: 0.27;
        }

        20.4% {
          opacity: 0.378;
        }

        23.8% {
          opacity: 0.502;
        }

        27.2% {
          opacity: 0.643;
        }

        30.6% {
          opacity: 0.803;
        }

        34%,
        44% {
          opacity: 1;
        }

        49.6% {
          opacity: 0.803;
        }

        55.2% {
          opacity: 0.643;
        }

        60.8% {
          opacity: 0.502;
        }

        66.4% {
          opacity: 0.378;
        }

        72% {
          opacity: 0.27;
        }

        77.6% {
          opacity: 0.178;
        }

        88.8% {
          opacity: 0.049;
        }

        100% {
          opacity: 0;
        }
      }

      /* the seams' own layer: no stacking context of its own, so a flash
         still rides above the scrim and a still stays under it */
      .cf-joins {
        position: absolute;
        inset: 0;
        pointer-events: none;
      }

      /**
       * A SEAM THAT COVERS THE FURNITURE (\`@over="everything"\`). Above the
       * type, the stamp, the rail, the inserts and the clips (1 to 4);
       * level with the transport, which is later in the document and so
       * stays in front of it; below the menu, the captions, the door and
       * the fault banner (6 and up). A viewer must never lose the
       * controls to a transition \u2014 and the layer takes no pointer events
       * either way. The class is on only while the seam runs.
       */
      .cf-joins.is-over {
        z-index: 5;
      }

      /* ---- the lens ------------------------------------------------- */
      /* THE CLOUD IS A CAST SHADOW, not a filter over the lens. A band
         swept across the whole frame reads as somebody dimming the
         picture; what a cloud actually does is drop a soft, uneven
         shape onto the land and the building, keep its edges out of
         focus, and move. Two overlapping blobs on a wide plate,
         multiplied over the scene and travelling with the sun's rake. */
      .cf-cloud {
        position: absolute;
        /* -35%/-45% was a plate 1.7x the viewport each way, blurred at 26px
           on every frame the sun moved. The gradients are soft already; the
           blur added nothing you could see and a full-screen filter you could
           feel. Smaller, unblurred, and hidden outright when there is no
           cloud \u2014 an opacity of zero still costs a composited layer. */
        inset: -12% -16%;
        z-index: 1;
        pointer-events: none;
        /* IT WAS BLUE, AND BARCELONA IS NOT. A cloud passing over a warm
           stone site takes the warmth out of the light; it does not tip the
           whole frame to slate. These are a warm grey now, and at half the
           strength \u2014 a shadow crossing the picture rather than a filter
           laid over it. */
        opacity: calc(var(--cf-cloud, 0) * 0.32);
        background:
          radial-gradient(
            62% 40% at 32% 44%,
            rgba(112, 100, 80, 0.4) 0%,
            rgba(120, 108, 88, 0.24) 46%,
            rgba(128, 118, 100, 0) 84%
          ),
          radial-gradient(
            48% 32% at 68% 58%,
            rgba(106, 96, 78, 0.3) 0%,
            rgba(122, 110, 90, 0.16) 52%,
            rgba(128, 118, 100, 0) 90%
          );
        mix-blend-mode: multiply;
        transform: rotate(calc(var(--cf-rake, 35deg) * 0.4))
          translate3d(
            calc(var(--cf-cloud, 0) * -16%),
            calc(var(--cf-cloud, 0) * 7%),
            0
          );
      }

      .is-cloudless .cf-cloud {
        visibility: hidden;
      }

      /* ---- scrims: anchored to the caption, never banded across the
         frame. A band wide enough to carry a lower third also washes out
         whatever is standing in the middle of the shot \u2014 which on this
         route is the building. ------------------------------------------ */
      .cf-scrim {
        position: absolute;
        inset: 0;
        z-index: 1;
        pointer-events: none;
        transition: background 700ms ease;
      }

      /* a bare beat: no scrim at all \u2014 under a walk through the hours the
         scrim's paper colour snaps with each theme, and a dish of colour
         snapping behind the type is worse than no dish */
      .cf-scrim.is-bare {
        display: none;
      }

      .cf-scrim-lower {
        background: radial-gradient(
          128% 82% at 0% 112%,
          var(--cf-paper-a) 0%,
          var(--cf-paper-b) 36%,
          var(--cf-paper-c) 72%
        );
      }

      .cf-scrim-title {
        background: radial-gradient(
          112% 108% at 112% 116%,
          var(--cf-paper-a) 0%,
          var(--cf-paper-b) 34%,
          var(--cf-paper-c) 70%
        );
      }

      .cf-scrim-plate {
        background: radial-gradient(
          84% 104% at 110% 50%,
          var(--cf-paper-a) 0%,
          var(--cf-paper-b) 34%,
          var(--cf-paper-c) 72%
        );
      }

      .cf-scrim-point {
        background: radial-gradient(
          88% 92% at -10% 26%,
          var(--cf-paper-a) 0%,
          var(--cf-paper-b) 38%,
          var(--cf-paper-c) 74%
        );
      }

      .cf-dim {
        position: absolute;
        inset: 0;
        z-index: 2;
        pointer-events: none;
        opacity: 0;
        background: radial-gradient(
          76% 66% at 50% 48%,
          rgba(24, 18, 8, 0.16) 0%,
          rgba(24, 18, 8, 0.34) 100%
        );
      }

      /* ---- traces and callouts -------------------------------------- */
      .cf-track {
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
        pointer-events: none;
        z-index: 2;
      }

      /* the marker glows, and the glow is doing real work: a thin line
         over moss competes with the moss at exactly its own frequency,
         and a soft bloom gives the eye a low-frequency edge to catch
         first. (The traces on the building carry their own glow shell in
         the scene now; this dresses only what is still on the glass.) */
      /* THE GLOW COSTS A FRAME IN SAFARI. These two elements move every
         frame \u2014 the leader is re-pointed at the building on each one \u2014 and
         a stacked pair of drop-shadow filters is re-rasterised each time,
         which WebKit charges far more for than Blink does. One tight
         shadow gives the eye the same low-frequency edge to catch; the
         wide one was doing very little over a dimmed plate anyway. */
      .cf-leader,
      .cf-track circle {
        filter: drop-shadow(0 0 3px rgba(255, 36, 18, 0.9));
      }

      .cf-tether {
        stroke: var(--cf-accent);
        stroke-width: 1.4;
        stroke-dasharray: 3 5;
        opacity: 0;
        transition: opacity 500ms ease;
      }

      .cf-leader {
        stroke: var(--cf-mark);
        stroke-width: 1.8;
        stroke-dasharray: 5 4;
        stroke-linecap: round;
        opacity: 0;
      }

      .cf-track circle {
        fill: none;
        stroke: var(--cf-mark);
        stroke-width: 2.6;
        stroke-linecap: round;
        opacity: 0;
      }

      /* ================================================================
         RESPONSIVE. The film had not one media query in it: every size was
         a viewport fraction, which keeps type in proportion but does not
         change a LAYOUT. Two columns of an editorial plate do not become
         a phone layout by getting smaller \u2014 they have to become one
         column, the ghost numeral has to go, and the settings have to
         stop being a corner of the frame and become its foot.
         ================================================================ */

      /* a laptop, or a window shared with something else */
      @media (max-width: 1180px) {
        .cf-block {
          max-width: min(38ch, 56vw);
        }

        .cf-block.is-plate {
          max-width: min(46ch, 52vw);
        }

        .is-plate .cf-kanji.is-latin {
          --cf-fit: 28vw;
          max-width: 30vw;
        }

        .cf-say {
          max-width: min(28ch, 42vw);
        }
      }

      /* a tablet, or a phone held the long way */
      @media (max-width: 860px) {
        /* the plate stops being two columns: the word goes over the cues,
           and the rule that separated them becomes the rule under it */
        .cf-block.is-plate {
          top: auto;
          bottom: 12%;
          right: 5.5%;
          left: 5.5%;
          display: block;
          transform: none;
          max-width: none;
        }

        .is-plate .cf-plane.is-glyph {
          border-right: 0;
          border-bottom: 2px solid var(--cf-chap);
          padding-right: 0;
          padding-bottom: 8px;
          margin-bottom: 14px;
        }

        /* stacked under the word, the cues read from the left again */
        .is-plate .cf-plane:not(.is-glyph) {
          align-items: flex-start;
          text-align: left;
        }

        .is-plate .cf-read {
          justify-content: flex-start;
        }

        .is-plate .cf-kanji.is-latin {
          --cf-fit: 84vw;
          max-width: none;
        }

        .cf-block.is-title,
        .cf-block.is-lower,
        .cf-block.is-point {
          left: 5.5%;
          right: 5.5%;
          top: auto;
          bottom: 13%;
          max-width: none;
          text-align: left;
        }

        .is-title .cf-read {
          justify-content: flex-start;
        }

        .is-title .cf-kicker {
          flex-direction: row;
        }

        .cf-kanji.is-latin,
        .is-title .cf-kanji.is-latin,
        .is-point .cf-kanji.is-latin {
          --cf-fit: 84vw;
        }

        .cf-say {
          max-width: min(32ch, 84vw);
        }

        /* a numeral three-quarters of the screen wide behind two columns
           of type is a texture; behind one column it is a mess */
        .cf-ghost,
        .cf-plate .cf-ghost {
          display: none;
        }

        .cf-photo figure {
          width: min(46vw, 260px);
        }

        /* a narrow frame: the rule drops under the title again */
        .cf-rail {
          flex-wrap: wrap;
        }

        .cf-years {
          flex-basis: 100%;
          width: clamp(200px, 56vw, 420px);
          margin-left: 0;
          margin-top: 8px;
        }

        .cf-subs {
          font-size: 15px;
          max-width: 88vw;
        }
      }

      /* a phone */
      @media (max-width: 560px) {
        .cf-kicker {
          font-size: 10px;
          letter-spacing: 0.09em;
        }

        .cf-say {
          font-size: 15px;
          margin-bottom: 8px;
        }

        .cf-read {
          margin-bottom: 12px;
        }

        .cf-kanji {
          margin-bottom: 12px;
        }

        .cf-gate-index,
        .cf-rail {
          display: none;
        }

        .cf-gate-in.cf-matter {
          margin-right: 0;
          padding-inline: 20px;
        }

        .cf-gate-vert {
          display: none;
        }

        .cf-mg-seal {
          position: static;
          margin: 14px auto 0;
        }

        .cf-photo {
          display: none;
        }

        .cf-subs {
          font-size: 14px;
          bottom: 10%;
        }
      }

      /* a short window: the film is 16:9 in a letterbox and the vertical
         rhythm, not the width, is what runs out */
      @media (max-height: 620px) {
        .cf-kanji.is-latin {
          font-size: min(
            clamp(30px, 8vh, 64px),
            calc(var(--cf-fit, 42vw) / (var(--cf-glyphs, 4) * 0.56))
          );
        }

        .cf-say {
          font-size: clamp(13px, 2.4vh, 18px);
          margin-bottom: 7px;
        }

        .cf-block.is-lower,
        .cf-block.is-title {
          bottom: 8%;
        }

        .has-subs .cf-block.is-lower,
        .has-subs .cf-block.is-title {
          bottom: 17%;
        }
      }

      /* someone who has asked for less movement gets the film without the
         drift, the sway and the entrances \u2014 and still gets the film */
      @media (prefers-reduced-motion: reduce) {
        .cf-mg-mark,
        .cf-mg-glyph,
        .cf-gate-ghost,
        .cf-mg-seal,
        .cf-kicker::after {
          animation-duration: 1ms !important;
        }
      }

      /* ---- the front layer ------------------------------------------ */
      /* THE WALL TEXT LEAVES BEFORE THE SEAM. Its own exit animation
         runs when the next beat replaces it, which means the outgoing
         setting is still on screen at the instant of the cut \u2014 so the
         edit lands on a frame with two things happening in it. Half a
         second of fade ahead of the change empties the corner first,
         and the cut is then only ever about the picture. */
      /* the ink follows the hour: the palette is swapped per theme by wear,
         and under a walk through the day the type must not snap from black
         to white \u2014 it turns with the light */
      .cf-type,
      .cf-type p,
      .cf-type span {
        transition: color 2400ms ease;
      }

      .cf-type {
        position: absolute;
        inset: 0;
        z-index: 3;
        opacity: var(--cf-type-a, 1);
        pointer-events: none;
        color: var(--cf-ink);
        font-family: var(--cf-display);
      }

      .cf-block {
        position: absolute;
        max-width: min(46vw, 660px);
      }

      /* a kicker rides a rule that draws itself out of the type \u2014 the
         diagonal is the sun's, so the graphic furniture rakes the same
         way the shadows do */
      /* the eyebrow never wraps: 'THE TALLEST CHURCH ON EARTH' at this
         tracking is wider than the block, and a wrapped kicker changes
         the height of a bottom-anchored plate */
      .cf-kicker > span {
        white-space: nowrap;
      }

      .cf-kicker {
        font-family: var(--cf-ui);
        font-size: clamp(11px, 0.9vw, 14px);
        font-weight: 700;
        letter-spacing: 0.11em;
        color: var(--cf-chap);
        margin: 0 0 14px;
        display: flex;
        align-items: center;
        gap: 12px;
      }

      /* the rule draws itself out of the kicker. It is a pseudo-element,
         so Motion cannot own it \u2014 but the whole block is rebuilt on every
         beat, which means a plain CSS animation runs from its first frame
         each time and needs no retriggering. */
      .cf-kicker::after {
        content: '';
        /* the rule takes the chapter's colour: on the centenary timeline
           the rule, the dot and the heading are one colour, and that is
           what makes it read as a system rather than as decoration */
        background: var(--cf-chap);
        /* the rule gives way to the words but never vanishes: a rule that
           collapses to nothing on a long kicker is furniture that blinks
           in and out with the string length */
        flex: 1 1 26px;
        min-width: 26px;
        height: 2px;
        transform-origin: left center;
        animation: cf-rule 760ms 300ms cubic-bezier(0.22, 1, 0.36, 1) both;
      }

      .is-title .cf-kicker::after {
        transform-origin: right center;
      }

      @keyframes cf-rule {
        from {
          transform: scaleX(0);
        }

        to {
          transform: scaleX(1);
        }
      }

      .is-point .cf-kicker::after,
      .is-lower .cf-kicker::after {
        max-width: 120px;
      }

      .cf-kanji {
        font-family:
          'Hiragino Mincho ProN', 'Yu Mincho', YuMincho, 'Noto Serif JP',
          'Songti SC', serif;
        font-size: clamp(56px, 8.4vw, 132px);
        line-height: 0.94;
        letter-spacing: 0.04em;
        margin: 0 0 18px;
      }

      .cf-read {
        margin: 0 0 20px;
        display: flex;
        gap: 6px 16px;
        align-items: baseline;
        flex-wrap: wrap;
      }

      /* a flex child cannot shrink past its own content without this */
      .cf-romaji,
      .cf-gloss {
        min-width: 0;
      }

      /* on a marked beat the reading is the largest thing in the block,
         because the term itself is out in the scene */
      .cf-block:not(:has(.is-glyph)) .cf-romaji {
        font-size: clamp(17px, 1.5vw, 24px);
        letter-spacing: 0.2em;
      }

      .cf-block:not(:has(.is-glyph)) .cf-gloss {
        font-size: clamp(15px, 1.2vw, 19px);
      }

      .cf-romaji {
        font-family: var(--cf-ui);
        font-size: clamp(11px, 0.94vw, 14px);
        font-weight: 700;
        letter-spacing: 0.11em;
        color: var(--cf-chap);
      }

      .cf-gloss {
        font-family: var(--cf-ui);
        font-size: clamp(12px, 0.98vw, 15px);
        font-weight: 400;
        letter-spacing: 0.01em;
        color: var(--cf-ink3);
      }

      /* the planes are the host's to move; the type on them is Motion's */
      .cf-plane {
        will-change: transform;
      }

      /* a phrase is a HEADLINE, not body copy: it is on screen for two
         seconds and read at a glance, so it is set at the size a glance
         needs and it never runs past two lines */
      .cf-say {
        margin: 0 0 12px;
        font-family: var(--cf-display);
        /* set in the identity's capitals, but a cue is still a caption:
           at 30px in heavy caps three of them fill a frame and the
           picture becomes the background to a poster */
        font-size: clamp(14px, 1.28vw, 22px);
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.012em;
        line-height: 1.16;
        color: var(--cf-ink);
        /* a cue is a phrase: wide enough that most set on ONE line.
           26ch was a CJK measure and these run to 34 characters, so the
           measure comes from the longest of them \u2014 and the break is left
           to pretty, because balance moves the break around as the
           string changes, which is the flicker between a one-line and a
           two-line setting. */
        max-width: min(38ch, 34vw);
        text-wrap: pretty;
      }

      .cf-say:last-child {
        margin-bottom: 0;
      }

      /* tall scripts (Thai, Khmer) at kanji size collide with their
         neighbours; scale the whole set box and give the marks headroom */
      .cf-kanji.is-tall {
        zoom: 0.58;
        line-height: 1.5;
      }

      /* ---- lines that DO what they SAY ------------------------------ *
         Behavior animations on the inner span, addressed per line by the
         film (\`.sx-<beat>-<n>\`). They run the length of the beat, so
         whenever the delivery reveals a line it is already mid-behavior \u2014
         never waiting, never done. Two gestures ship here: a plumb drop
         and a heavy settle. */
      .cf-sayx {
        display: inline-block;
      }

      @keyframes cf-plumb {
        0% {
          transform: translateY(-16px) scaleY(1.18);
        }

        100% {
          transform: translateY(0) scaleY(1);
        }
      }

      /* "Flaring at the foot" \u2014 the line itself flares, tracking wide
         from its left foot for the whole shot, the batter's own curve */
      /* (the old per-line behaviours are gone: one of them animated
         letter-spacing on an inline-block, which re-wrapped the line it
         was in halfway through a shot) */

      @keyframes cf-sink {
        0% {
          transform: translateY(-14px);
        }

        34% {
          transform: translateY(2px);
        }

        100% {
          transform: translateY(0);
        }
      }

      /* the four ways a beat is set. A title is ranged right against the
         frame's edge with the tower in the other half; a lower third sits
         bottom-left; a plate is a slab in the right third; a point is a
         caption with a leader running out of it. */
      .cf-block.is-title {
        right: 6%;
        bottom: 15%;
        text-align: right;
        max-width: min(48vw, 700px);
        /* poster size at the start, the house size once the lens has
           arrived: the same lean as every block, times the title's own
           scale, from the corner it hangs from */
        transform-origin: 100% 100%;
        transform: translate3d(
            calc(var(--cf-lx, 0) * -9px),
            calc(var(--cf-ly, 0) * -5px),
            0
          )
          scale(calc(1.42 - 0.42 * var(--cf-title-k, 1)));
      }

      /* the opening's hierarchy: the name, then its reading, then the
         cues a step back in the ink \u2014 a poster, not a paragraph */
      .is-title .cf-kanji {
        margin-bottom: 26px;
      }

      .is-title .cf-read {
        justify-content: flex-end;
        margin-bottom: 28px;
        gap: 18px;
      }

      .is-title .cf-romaji {
        font-size: clamp(15px, 1.3vw, 23px);
        letter-spacing: 0.3em;
      }

      .is-title .cf-gloss {
        font-size: clamp(15px, 1.25vw, 22px);
      }

      .is-title .cf-say {
        max-width: 30ch;
        margin-bottom: 6px;
        color: var(--cf-ink2);
        font-size: clamp(19px, 1.95vw, 34px);
      }

      .is-title .cf-kicker {
        flex-direction: row-reverse;
      }

      .is-title .cf-line {
        margin-left: auto;
      }

      .is-title .cf-kanji {
        font-size: clamp(72px, 11vw, 190px);
      }

      .cf-block.is-lower {
        left: 5.5%;
        bottom: 11%;
      }

      /* captions take the foot of the frame, so the settings that live
         down there move up out of their way rather than sit under them */
      .has-subs .cf-block.is-lower {
        bottom: 21%;
      }

      /* the plate steps out of the caption band's way \u2014 and stepping is
         what it should not do, so it moves over a beat, not a frame */
      .cf-block {
        transition: bottom 420ms cubic-bezier(0.22, 1, 0.36, 1);
      }

      .has-subs .cf-block.is-title {
        bottom: 24%;
      }

      /* the plate is centred on the frame, so a caption band eats its last
         cue rather than sitting under it */
      .has-subs .cf-block.is-plate {
        top: 44%;
      }

      /* THE PLATE, which is the one setting that is a designed object
         rather than a caption. Two columns: the term set VERTICALLY down
         the right edge, the way it would be on a museum label or a
         hanging scroll, and the reading and the phrases in a column
         beside it. A rule between them draws itself down as the plate
         lands. Ranged type in a corner was never wrong exactly \u2014 it was
         just nothing, and this chapter's beats are the ones that hold
         longest, so they are the ones that can least afford nothing. */
      .cf-block.is-plate {
        right: 5.5%;
        top: 50%;
        transform: translateY(-50%);
        display: grid;
        /* minmax(0,\u2026) or the cue column cannot shrink and the word wins */
        grid-template-columns: minmax(0, auto) auto;
        justify-content: end;
        column-gap: clamp(16px, 1.8vw, 30px);
        align-items: start;
        /* the word takes a column of its own, so the block has to be wide
           enough for both it and a cue line that is not two words per row
           \u2014 and no wider: at two thirds of the frame the cue column began
           over the subject, and a plate is a label beside the thing */
        max-width: min(50vw, 760px);
      }

      .is-plate .cf-plane {
        grid-column: 1;
      }

      /* THE CUES RANGE AGAINST THE RULE. The block hugs the right edge and
         everything in it gathers toward the word, so the plate is one
         object at the side of the frame and the picture keeps its left. */
      .is-plate .cf-plane:not(.is-glyph) {
        display: flex;
        flex-direction: column;
        align-items: flex-end;
        text-align: right;
      }

      .is-plate .cf-plane:not(.is-glyph) .cf-kicker {
        align-self: stretch;
      }

      .is-plate .cf-read {
        justify-content: flex-end;
      }

      .is-plate .cf-plane.is-glyph {
        grid-column: 2;
        grid-row: 1 / -1;
        border-right: 2px solid var(--cf-accent);
        padding-right: clamp(14px, 1.5vw, 26px);
        transform-origin: top center;
        animation: cf-rule-down 820ms 240ms cubic-bezier(0.22, 1, 0.36, 1) both;
      }

      /* the mask draws the rule DOWN; it must never clip sideways \u2014 the
         glyph plane leans with the pointer, and a mask flush with the box
         shaved the leaned strokes off the left edge as a hairline */
      @keyframes cf-rule-down {
        from {
          clip-path: inset(0 -40px 100% -40px);
        }

        to {
          clip-path: inset(0 -40px -4% -40px);
        }
      }

      .is-plate .cf-kanji {
        writing-mode: vertical-rl;
        margin: 0;
        /* the column never grows past the frame: whichever is smaller,
           the designed size or the height each glyph can have and still
           leave the set inside the picture */
        font-size: min(
          clamp(44px, 5.4vw, 88px),
          calc(62svh / var(--cf-glyphs, 3))
        );
        letter-spacing: 0.1em;
        line-height: 1;
      }

      .is-plate .cf-kicker {
        margin-bottom: 18px;
      }

      /* the ghost is only ever behind a plate \u2014 everywhere else the frame
         is already carrying the building */
      .cf-ghost {
        display: none;
      }

      /* THE PLANES LEAN. Each layer takes the pointer at its own depth \u2014
         the ghost furthest, the big glyph next, the reading lines least
         \u2014 so the type stack has air in it rather than being one sheet
         of glass in front of a picture. */
      .cf-block {
        transform: translate3d(
          calc(var(--cf-lx, 0) * -9px),
          calc(var(--cf-ly, 0) * -5px),
          0
        );
      }

      .cf-plate .cf-ghost {
        transform: translateY(-50%)
          translate3d(
            calc(var(--cf-lx, 0) * -26px),
            calc(var(--cf-ly, 0) * -14px),
            0
          );
      }

      .cf-kanji {
        transform: translate3d(
          calc(var(--cf-lx, 0) * -15px),
          calc(var(--cf-ly, 0) * -8px),
          0
        );
      }

      /* the ghost NUMERAL keeps its old treatment: a filled slab of ink
         at a whisper of opacity, behind the plate. It is a page
         furniture mark, not type in the world \u2014 the hollow treatment
         belongs to the glyphs that share air with the building. */
      .cf-plate .cf-ghost {
        display: block;
        position: absolute;
        right: 3%;
        top: 50%;
        transform: translateY(-50%);
        font-family: var(--cf-ui);
        font-size: clamp(180px, 30vw, 460px);
        font-weight: 700;
        line-height: 0.8;
        letter-spacing: -0.04em;
        color: var(--cf-ink);
        opacity: calc(0.045 * var(--cf-ghost-a, 1));
        pointer-events: none;
        z-index: -1;
      }

      .cf-block.is-point {
        left: 5.5%;
        top: 18%;
        max-width: min(36vw, 520px);
      }

      .is-point .cf-kanji {
        font-size: clamp(48px, 6.6vw, 104px);
      }

      /* ---- clips ------------------------------------------------------ *
         a video, a still or a freeze over the picture: full frame under the
         scrim and the type, or an inset like the photograph */
      .cf-clip {
        position: absolute;
        pointer-events: none;
      }

      .cf-clip.is-cover {
        inset: 0;
        z-index: 1;
      }

      .cf-clip.is-cover figure {
        position: absolute;
        inset: 0;
        margin: 0;
      }

      .cf-clip.is-cover video,
      .cf-clip.is-cover img {
        display: block;
        width: 100%;
        height: 100%;
        object-fit: cover;
      }

      .cf-clip.is-cover figcaption {
        position: absolute;
        left: 5.5%;
        bottom: 6%;
        display: flex;
        flex-direction: column;
        gap: 2px;
        font-family: var(--cf-ui);
        color: #f7f0e0;
        text-shadow: 0 1px 12px rgba(0, 0, 0, 0.5);
      }

      .cf-clip.is-inset {
        z-index: 4;
      }

      /**
       * A PIP IS A LAYER, not a photograph. No card, no rule, no caption
       * furniture \u2014 the score places it (\`left/top/width\` in percent of
       * the frame, written inline) and it carries nothing but its own
       * media and a corner radius. It sits under the type, so a lower
       * third still wins over it, and over the picture and its scrim.
       */
      .cf-clip.is-pip {
        z-index: 2;
        inset: 0;
      }

      .cf-clip.is-pip figure {
        position: absolute;
        margin: 0;
        overflow: hidden;
        line-height: 0;
        box-shadow: calc(var(--cf-shx) * 3) calc(var(--cf-shy) * 3) 30px
          rgba(20, 14, 4, 0.34);
      }

      .cf-clip.is-pip video,
      .cf-clip.is-pip img {
        display: block;
        width: 100%;
        height: auto;
      }

      .cf-clip.is-inset figure {
        position: absolute;
        right: 5.5%;
        top: 12%;
        margin: 0;
        width: min(30vw, 340px);
        background: var(--cf-paper);
        padding: 10px 10px 8px;
        border: 1px solid var(--cf-rule);
        box-shadow: calc(var(--cf-shx) * 4) calc(var(--cf-shy) * 4) 26px
          rgba(38, 28, 10, 0.26);
      }

      .cf-clip.is-inset video,
      .cf-clip.is-inset img {
        display: block;
        width: 100%;
        height: auto;
      }

      .cf-clip.is-inset figcaption {
        display: flex;
        flex-direction: column;
        gap: 2px;
        padding-top: 8px;
        font-family: var(--cf-ui);
      }

      .cf-clip-cap {
        font-size: 12px;
        font-weight: 700;
        letter-spacing: 0.12em;
      }

      .cf-clip-cr {
        font-size: 10px;
        letter-spacing: 0.06em;
        opacity: 0.75;
      }

      /* ---- the photograph -------------------------------------------- */
      .cf-photo {
        position: absolute;
        z-index: 4;
        pointer-events: none;
      }

      .cf-photo figure.is-lower,
      .cf-photo figure.is-title,
      .cf-photo figure.is-point {
        position: absolute;
        right: 5.5%;
        top: 12%;
      }

      .cf-photo figure.is-plate {
        position: absolute;
        left: 5.5%;
        top: 12%;
      }

      .cf-photo figure {
        margin: 0;
        width: min(30vw, 340px);
        background: var(--cf-paper);
        padding: 10px 10px 8px;
        border: 1px solid var(--cf-rule);
        box-shadow: calc(var(--cf-shx) * 4) calc(var(--cf-shy) * 4) 26px
          rgba(38, 28, 10, 0.26);
      }

      .cf-photo img {
        display: block;
        width: 100%;
        height: auto;
        filter: saturate(0.86) contrast(1.04);
      }

      .cf-photo figcaption {
        display: flex;
        flex-direction: column;
        gap: 2px;
        padding-top: 8px;
        font-family: var(--cf-ui);
      }

      .cf-photo-cap {
        font-size: 12px;
        font-weight: 700;
        letter-spacing: 0.12em;
        color: var(--cf-ink);
      }

      .cf-photo-cr {
        font-size: 10px;
        letter-spacing: 0.06em;
        color: var(--cf-ink2);
      }

      .is-dark .cf-subs {
        color: #1a1408;
        background: rgba(238, 228, 204, 0.82);
      }

      .cf-subs {
        position: absolute;
        left: 50%;
        bottom: 3%;
        transform: translateX(-50%);
        z-index: 6;
        transition: bottom 360ms ease;
        margin: 0;
        max-width: 60ch;
        text-align: center;
        font-family: var(--cf-serif);
        font-size: 17px;
        line-height: 1.5;
        color: #f7efdd;
        background: rgba(20, 15, 6, 0.66);
        padding: 9px 18px;
      }

      /* while the transport is up the caption sits above it, and drops
         back to the foot of the frame when the bar leaves */
      .cf-page:not(.is-idle) .cf-subs {
        bottom: 104px;
      }

      /* ---- the rail -------------------------------------------------- */
      /* ONE LINE: the numeral, the chapter's name and the rule, left to
         right \u2014 the rule is not a second row under the title */
      .cf-rail {
        flex-wrap: nowrap;
        position: absolute;
        left: 5.5%;
        top: 6%;
        z-index: 3;
        display: flex;
        align-items: center;
        gap: 14px;
        font-size: 11px;
        font-weight: 700;
        letter-spacing: 0.17em;
        color: var(--cf-ink3);
        font-family: var(--cf-ui);
      }

      .cf-rail-n {
        font-size: 22px;
        font-weight: 800;
        letter-spacing: 0.02em;
        color: var(--cf-chap);
      }

      .cf-rail-segs {
        display: flex;
        gap: 5px;
        width: 240px;
      }

      /* ---- the year's own timeline ----------------------------------
         A rule the width of the chapter strip, the run so far filled in
         the chapter's colour, a dot on the head and the year riding above
         it. Tabular figures so the numeral does not jitter as it counts,
         and the whole thing is one row under the chapter line so the
         corner stays a single object. */
      /* THE RULE IS THE FILM'S LENGTH, so it should read as a long
         distance: 240px made a century and a half look like a widget.
         It runs to nearly half the frame now, and the chapter dots have
         room to sit at their own years without touching. */
      .cf-years {
        position: relative;
        flex: none;
        height: 34px;
        margin-left: 34px;
        width: clamp(260px, 42vw, 620px);
      }

      .cf-years-rule,
      .cf-years-fill {
        position: absolute;
        left: 0;
        top: 14px;
        height: 2px;
        background: var(--cf-rule);
      }

      .cf-years-rule {
        right: 0;
      }

      .cf-years-fill {
        width: calc(5px + var(--cf-head, 0) * (100% - 10px));
        background: var(--cf-chap);
        transition: width 220ms linear;
      }

      .cf-years-tick {
        position: absolute;
        top: 11px;
        width: 1px;
        height: 8px;
        background: var(--cf-rule);
      }

      /* the chapters, as dots at the years they open. Unbuilt they are the
         rule's own colour; passed, they take the chapter's. */
      .cf-years-ch {
        position: absolute;
        top: 10px;
        z-index: 2;
        appearance: none;
        border: 0;
        padding: 0;
        width: 10px;
        height: 10px;
        margin-left: -5px;
        border-radius: 50%;
        background: var(--cf-rule);
        cursor: pointer;
        pointer-events: auto;
        transition:
          background 300ms ease,
          transform 200ms ease;
      }

      .cf-years-ch.is-done {
        background: var(--cf-chap);
      }

      .cf-years-ch.is-here {
        background: var(--cf-chap);
        transform: scale(1.34);
      }

      .cf-years-ch:hover {
        transform: scale(1.5);
      }

      .cf-years-now {
        position: absolute;
        top: 20px;
        left: calc(5px + var(--cf-head, 0) * (100% - 10px));
        transform: translateX(-50%);
        font-family: var(--cf-ui);
        font-weight: 800;
        font-size: 15px;
        letter-spacing: 0.01em;
        font-variant-numeric: tabular-nums;
        color: var(--cf-chap);
        white-space: nowrap;
        transition: left 220ms linear;
      }

      .cf-years-now::after {
        content: '';
        position: absolute;
        left: 50%;
        /* rule top 14px, rule 2px, dot 10px \u2192 -10 puts the dot's centre
           on the rule's centre exactly */
        top: -10px;
        width: 10px;
        height: 10px;
        margin-left: -5px;
        border-radius: 50%;
        background: var(--cf-chap);
      }

      .cf-years-a,
      .cf-years-b {
        position: absolute;
        top: 0;
        font-family: var(--cf-ui);
        font-style: normal;
        font-size: 9px;
        font-weight: 600;
        letter-spacing: 0.14em;
        color: var(--cf-ink2);
      }

      .cf-years-a {
        left: 0;
      }

      .cf-years-b {
        right: 0;
      }

      /* each segment is a 13px-tall click target drawing a hairline
         track with its fill on top; the current chapter's bar thickens */
      .cf-rail-seg {
        appearance: none;
        position: relative;
        border: 0;
        height: 13px;
        padding: 0;
        background: transparent;
        cursor: pointer;
        pointer-events: auto;
      }

      .cf-rail-seg::after {
        content: '';
        position: absolute;
        inset: 5px 0 auto;
        height: 3px;
        background: var(--cf-rule);
      }

      .cf-rail-seg i {
        position: absolute;
        left: 0;
        top: 5px;
        height: 3px;
        z-index: 1;
        background: var(--cf-chap);
        transition: width 600ms cubic-bezier(0.22, 1, 0.36, 1);
      }

      .cf-rail-seg.is-here i {
        top: 4px;
        height: 5px;
      }

      /* THE DOT ON THE RULE. The centenary programme draws its timeline as
         a line with a filled dot at each momentum; the film's chapter
         strip is the same object, so it is drawn the same way. */
      .cf-rail-seg::before {
        content: '';
        position: absolute;
        left: -1px;
        top: 2px;
        z-index: 2;
        width: 9px;
        height: 9px;
        border-radius: 50%;
        background: var(--cf-rule);
        transition: background 300ms ease;
      }

      .cf-rail-seg.is-here::before {
        background: var(--cf-chap);
      }

      .cf-rail-seg:hover::after {
        background: var(--cf-ink2);
      }

      .cf-fault {
        position: absolute;
        left: 5.5%;
        bottom: 4%;
        z-index: 9;
        margin: 0;
        padding: 8px 12px;
        background: #2a0a06;
        color: #ffb4a0;
        font:
          12px/1.4 ui-monospace,
          monospace;
        border-radius: 8px;
        max-width: 80%;
      }

      .cf-rig {
        position: absolute;
        width: 0;
        height: 0;
      }

      /* ---- the disc menu --------------------------------------------- */
      /* the sheet belongs to the picture: it scrims the scene and its
         transport, and leaves the wall plate below the film alone \u2014
         a menu that dims an article is a modal, not a disc menu */
      .cf-menu {
        position: absolute;
        inset: 0 0 auto 0;
        height: 100svh;
        z-index: 6;
        display: flex;
        align-items: center;
        justify-content: center;
        background: rgba(28, 22, 10, 0.52);
        backdrop-filter: blur(2px);
      }

      .cf-menu-in {
        background: var(--cf-paper);
        border: 1px solid var(--cf-rule);
        padding: 34px 40px 26px;
        min-width: min(460px, 84vw);
        max-width: min(640px, 92vw);
        box-shadow: 0 30px 70px rgba(30, 22, 8, 0.34);
        font-family: var(--cf-ui);
      }

      .cf-menu-head {
        margin: 0;
        font-size: 13px;
        font-weight: 800;
        letter-spacing: 0.42em;
        color: var(--cf-ink);
      }

      .cf-menu-sub {
        margin: 4px 0 22px;
        font-size: 12px;
        color: var(--cf-ink2);
        letter-spacing: 0.06em;
      }

      .cf-menu-list {
        list-style: none;
        margin: 0 0 18px;
        padding: 0;
      }

      .cf-menu-item {
        appearance: none;
        background: transparent;
        border: 0;
        border-top: 1px solid var(--cf-rule);
        width: 100%;
        display: flex;
        align-items: baseline;
        gap: 16px;
        padding: 13px 4px;
        font: inherit;
        color: var(--cf-ink);
        cursor: pointer;
        text-align: left;
      }

      .cf-menu-item:hover {
        color: var(--cf-accent);
      }

      .cf-menu-item.is-here {
        color: var(--cf-accent);
        font-weight: 700;
      }

      .cf-menu-n {
        font-size: 12px;
        letter-spacing: 0.16em;
        color: var(--cf-accent);
        min-width: 2.4em;
      }

      .cf-menu-t {
        font-size: 17px;
        letter-spacing: 0.1em;
        font-weight: 600;
        flex: 1;
        min-width: 0;
      }

      .cf-menu-d {
        font-size: 11px;
        letter-spacing: 0.1em;
        color: var(--cf-ink2);
      }

      .cf-menu-keys {
        margin: 0;
        font-size: 11px;
        letter-spacing: 0.1em;
        color: var(--cf-ink2);
      }

      /* ---- controls -------------------------------------------------- */
      /* ---- the player ------------------------------------------------ *
       * A chaptered playhead in the film's own materials: gaps between
       * the chapters, seal red for what has played, and a head you can
       * take hold of. It sits ON the picture, above the transport, and
       * both stand down when the hand goes away.
       * ------------------------------------------------------------- */
      /* THE PLAYER FLOATS ON THE PICTURE, the way every player does \u2014
         a paper bar under the frame costs fifty pixels of film and
         announces that this is a document with a video in it. */
      /* THE BAR IS UNDER THE PICTURE, not on it. A player floating over
         the frame is right for a video in a page and wrong for a film
         that fills the window: it takes the bottom of every composition
         and it disappears exactly when you reach for it. Below the
         picture it costs seventy-six pixels once and is always there. */
      /* THE TRANSPORT SITS ON THE PICTURE, not under it. The source page
         runs its track as a hairline over the scene; here the strip was a
         solid band of paper that took 76px off every frame. It is a fade
         of the chapter's own paper now, so the film owns the whole
         viewport and the controls read as a ledge on the glass. */
      /* ---- the player ------------------------------------------------ */
      /* fixed, not absolute: the page runs on below the stage, so the
         page's bottom is not the frame's bottom. A dark scrim, not paper:
         white type on a gradient into black is the one thing that reads
         over every grade the film wears, and it is what the eye expects
         at the bottom of a picture that plays. */
      .cf-player {
        position: fixed;
        left: 0;
        right: 0;
        bottom: 0;
        z-index: 5;
        padding: 26px 14px 8px;
        color: #fff;
        font-family: var(--cf-ui);
        background: linear-gradient(
          to top,
          rgba(12, 9, 4, 0.72),
          rgba(12, 9, 4, 0.38) 45%,
          rgba(12, 9, 4, 0)
        );
        transition: opacity 360ms ease;
      }

      /* nobody is touching it: the apparatus leaves the picture, the way
         every player made since 2010 does; a hand on the frame brings it
         back (wake) */
      .cf-player.is-idle {
        opacity: 0;
        pointer-events: none;
      }

      /* the transport waits outside while the front door is open */
      .cf-player.is-away {
        visibility: hidden;
      }

      .cf-scrub {
        position: relative;
        height: 22px;
        display: flex;
        align-items: center;
        cursor: pointer;
        touch-action: none;
        outline: none;
      }

      .cf-scrub-track {
        position: relative;
        display: flex;
        gap: 2px;
        width: 100%;
        height: 3px;
        transition: height 120ms ease;
      }

      .cf-scrub:hover .cf-scrub-track,
      .cf-scrub:focus-visible .cf-scrub-track {
        height: 5px;
      }

      .cf-scrub-ch {
        position: relative;
        overflow: hidden;
        background: rgba(255, 255, 255, 0.28);
        transition: transform 120ms ease;
      }

      /* the chapter under the pointer stands up a little, the way the
         hovered chapter on every chaptered bar does */
      .cf-scrub:hover .cf-scrub-ch:hover {
        transform: scaleY(1.7);
      }

      /* the ghost: a pale fill to wherever the pointer is resting, so
         the eye reads the cut it would make before the hand makes it */
      .cf-scrub-ch em {
        position: absolute;
        inset: 0 auto 0 0;
        display: block;
        background: rgba(255, 255, 255, 0.34);
        width: calc(
          clamp(0, (var(--cf-hov, 0) - var(--s0)) / var(--sl), 1) * 100%
        );
      }

      /* each chapter fills with the part of the whole-film playhead that
         falls inside it \u2014 one custom property, updated per frame, and no
         re-render anywhere */
      .cf-scrub-ch i {
        position: absolute;
        inset: 0 auto 0 0;
        display: block;
        background: var(--cf-red);
        width: calc(
          clamp(0, (var(--cf-prog, 0) - var(--s0)) / var(--sl), 1) * 100%
        );
      }

      /* the knob sits on the fill's end: --cf-hpx is that end in pixels,
         from the same fractions and the measured track (see frame) */
      .cf-scrub-head {
        position: absolute;
        top: 50%;
        left: calc(var(--cf-hpx, 0) * 1px);
        width: 13px;
        height: 13px;
        margin: -6.5px 0 0 -6.5px;
        border-radius: 50%;
        background: var(--cf-red);
        transform: scale(0);
        transition: transform 120ms ease;
      }

      .cf-scrub:hover .cf-scrub-head,
      .cf-scrub:focus-visible .cf-scrub-head,
      .cf-scrub.is-live .cf-scrub-head {
        transform: scale(1);
      }

      .cf-scrub-tip {
        position: absolute;
        bottom: 18px;
        left: calc(var(--cf-tipx, 0) * 1px);
        transform: translateX(-50%);
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 2px;
        white-space: nowrap;
        background: rgba(12, 9, 4, 0.92);
        color: #fff;
        padding: 7px 11px 6px;
        border-radius: 4px;
        pointer-events: none;
      }

      .cf-scrub-tip small {
        font-size: 10px;
        letter-spacing: 0.12em;
        color: rgba(255, 255, 255, 0.72);
      }

      .cf-scrub-tip b {
        font-size: 13px;
        font-weight: 600;
        font-variant-numeric: tabular-nums;
      }

      .cf-controls {
        display: flex;
        align-items: center;
        gap: 2px;
        height: 40px;
      }

      /* the round ghost button: a 40px target, the glyph 22px inside it,
         a hover that is a wash rather than an outline */
      .cf-ic {
        appearance: none;
        border: 0;
        background: transparent;
        color: #fff;
        width: 40px;
        height: 40px;
        padding: 0;
        border-radius: 50%;
        cursor: pointer;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        flex: none;
        opacity: 0.92;
        transition:
          background 120ms ease,
          opacity 120ms ease;
      }

      .cf-ic svg {
        width: 22px;
        height: 22px;
        fill: currentColor;
        display: block;
      }

      .cf-ic:hover,
      .cf-ic:focus-visible {
        background: rgba(255, 255, 255, 0.14);
        opacity: 1;
        outline: none;
      }

      /* the label above a button \u2014 the name and its key \u2014 in the bar's
         own bubble rather than the browser's slow yellow one */
      [data-tip] {
        position: relative;
      }

      [data-tip]::before {
        content: attr(data-tip);
        position: absolute;
        bottom: calc(100% + 10px);
        left: 50%;
        transform: translate(-50%, 4px);
        white-space: nowrap;
        background: rgba(12, 9, 4, 0.92);
        color: #fff;
        font-family: var(--cf-ui);
        font-size: 11px;
        font-weight: 500;
        letter-spacing: 0.06em;
        text-transform: none;
        padding: 6px 10px;
        border-radius: 4px;
        opacity: 0;
        pointer-events: none;
        transition:
          opacity 120ms ease 200ms,
          transform 120ms ease 200ms;
      }

      [data-tip]:hover::before,
      [data-tip]:focus-visible::before {
        opacity: 1;
        transform: translate(-50%, 0);
      }

      /* the last button's bubble hugs the right edge instead of the
         button's centre, so it never leaves the viewport */
      .cf-ic-last::before {
        left: auto;
        right: 0;
        transform: translate(0, 4px);
      }

      .cf-ic-last:hover::before,
      .cf-ic-last:focus-visible::before {
        transform: translate(0, 0);
      }

      /* the speaker and its fader: the fader is folded away until the
         pointer is on the speaker, then slides out beside it */
      .cf-vol {
        display: inline-flex;
        align-items: center;
      }

      .cf-vol-range {
        appearance: none;
        -webkit-appearance: none;
        width: 0;
        height: 3px;
        margin: 0;
        opacity: 0;
        border-radius: 2px;
        background: linear-gradient(
          to right,
          #fff calc(var(--cf-vol, 1) * 100%),
          rgba(255, 255, 255, 0.3) 0
        );
        cursor: pointer;
        outline: none;
        transition:
          width 200ms ease,
          margin 200ms ease,
          opacity 200ms ease;
      }

      .cf-vol:hover .cf-vol-range,
      .cf-vol:focus-within .cf-vol-range {
        width: 64px;
        margin: 0 12px 0 4px;
        opacity: 1;
      }

      .cf-vol-range::-webkit-slider-thumb {
        -webkit-appearance: none;
        appearance: none;
        width: 12px;
        height: 12px;
        border-radius: 50%;
        background: #fff;
        border: 0;
      }

      .cf-vol-range::-moz-range-thumb {
        width: 12px;
        height: 12px;
        border-radius: 50%;
        background: #fff;
        border: 0;
      }

      /* the chapter's name, beside the clock, is the way into the list */
      .cf-chap {
        appearance: none;
        border: 0;
        background: transparent;
        color: rgba(255, 255, 255, 0.78);
        font: inherit;
        font-size: 12.5px;
        letter-spacing: 0.04em;
        display: inline-flex;
        align-items: center;
        gap: 5px;
        height: 32px;
        padding: 0 6px 0 2px;
        border-radius: 4px;
        cursor: pointer;
        white-space: nowrap;
        max-width: min(34ch, 26vw);
        transition: color 120ms ease;
      }

      .cf-chap span {
        opacity: 0.6;
        padding-right: 1px;
      }

      .cf-chap svg {
        width: 14px;
        height: 14px;
        flex: none;
        fill: currentColor;
        opacity: 0.7;
        transition: transform 160ms ease;
      }

      .cf-chap:hover,
      .cf-chap:focus-visible {
        color: #fff;
        outline: none;
      }

      .cf-chap:hover svg {
        transform: translateX(2px);
      }

      /* a button with its name on it, set like the link beside it */
      .cf-word {
        appearance: none;
        border: 0;
        background: transparent;
        color: rgba(255, 255, 255, 0.82);
        font-family: var(--cf-ui);
        font-size: 11px;
        letter-spacing: 0.1em;
        text-transform: uppercase;
        display: inline-flex;
        align-items: center;
        gap: 7px;
        height: 32px;
        padding: 0 12px 0 8px;
        border-radius: 16px;
        cursor: pointer;
        white-space: nowrap;
        transition:
          background 120ms ease,
          color 120ms ease;
      }

      .cf-word svg {
        width: 18px;
        height: 18px;
        fill: currentColor;
      }

      .cf-word:hover,
      .cf-word:focus-visible {
        background: rgba(255, 255, 255, 0.14);
        color: #fff;
        outline: none;
      }

      /* the confirmation glyph, fixed at the middle of the picture */
      .cf-burst {
        position: fixed;
        left: 50%;
        top: 50%;
        width: 88px;
        height: 88px;
        margin: -44px 0 0 -44px;
        border-radius: 50%;
        background: rgba(12, 9, 4, 0.55);
        display: flex;
        align-items: center;
        justify-content: center;
        pointer-events: none;
        z-index: 4;
        animation: cf-burst 560ms ease-out forwards;
      }

      .cf-burst svg {
        width: 42px;
        height: 42px;
        fill: #fff;
      }

      @keyframes cf-burst {
        from {
          opacity: 1;
          transform: scale(0.72);
        }

        to {
          opacity: 0;
          transform: scale(1.5);
        }
      }

      /* the hand that stopped moving takes its pointer with it */
      .cf-page.is-idle {
        cursor: none;
      }

      /* CC is a word, set as a badge; on, it is underlined in the film's
         red the way every captions button on earth is */
      .cf-ic-cc {
        font-size: 11px;
        font-weight: 700;
        letter-spacing: 0.06em;
        position: relative;
      }

      .cf-ic-cc.is-on::after,
      .cf-ic.is-on::after {
        content: '';
        position: absolute;
        left: 13px;
        right: 13px;
        bottom: 7px;
        height: 2px;
        background: var(--cf-red);
        border-radius: 1px;
      }

      .cf-ic.is-on {
        position: relative;
      }

      .cf-time {
        margin-left: 8px;
        font-size: 12.5px;
        letter-spacing: 0.02em;
        font-variant-numeric: tabular-nums;
        color: rgba(255, 255, 255, 0.82);
        white-space: nowrap;
      }

      .cf-time b {
        font-weight: 500;
        color: #fff;
      }

      .cf-time i {
        font-style: normal;
        padding: 0 4px;
        opacity: 0.6;
      }

      /* the chapter title cannot be allowed to widen the control row */
      .cf-time em {
        display: inline-block;
        max-width: min(28ch, 22vw);
        overflow: hidden;
        text-overflow: ellipsis;
        vertical-align: bottom;
        font-style: normal;
        margin-left: 6px;
        color: rgba(255, 255, 255, 0.72);
      }

      .cf-spacer {
        flex: 1 1 auto;
      }

      .cf-link {
        color: rgba(255, 255, 255, 0.82);
        text-decoration: none;
        font-size: 11px;
        letter-spacing: 0.1em;
        text-transform: uppercase;
        padding: 0 12px;
        white-space: nowrap;
      }

      .cf-link:hover {
        color: #fff;
        text-decoration: underline;
        text-underline-offset: 3px;
      }

      /* only ever under ?debug: which cut of the film the browser has */
      .cf-build {
        color: rgba(255, 255, 255, 0.55);
        font:
          10px/1 ui-monospace,
          monospace;
        letter-spacing: 0.04em;
        padding: 0 12px;
        white-space: nowrap;
      }

      /* embedded, the iframe wraps the film AND its transport directly;
         the app's own chrome inside the iframe stands down instead */
      body.cf-embedded .topbar,
      body.cf-embedded .footer {
        display: none;
      }

      /* THE FILM ESCAPES THE APP'S PAGE CONTAINER. .page centres a
         measured column with gutters and a top offset \u2014 right for every
         demo page, and a pink-tinted mat around a film that owns its
         frame. Both film bodies flatten it; the film's own layout is the
         page. (This mattered only once cf-page left position: fixed \u2014
         fixed elements never felt the container.) */
      body.cf-film .page,
      body.cf-embedded .page {
        width: 100%;
        margin: 0;
        padding: 0;
      }

      /* a clear beat owns nothing on the glass, the numeral included */
      .cf-clear .cf-ghost {
        display: none;
      }

      /* ---- the gate --------------------------------------------------- */
      /* the card stands BESIDE the tower, never over it: the boot pose
         seats the building left of centre, so the door takes the right
         third \u2014 the same real estate the title beat's type owns \u2014 and
         its wash leans that way too instead of dimming the whole frame */
      /* THE DOOR DOES NOT BLUR THE BUILDING. A poster's job is to make
         the subject look like the reason to press play; a blur makes it
         look like a placeholder. The scene stays sharp and keeps
         turning (see the poster orbit) \u2014 the only thing over it is a
         ground for the type, raked away from the tower. */
      .cf-gate {
        position: absolute;
        inset: 0;
        z-index: 7;
        display: flex;
        align-items: center;
        justify-content: flex-end;
        background: linear-gradient(
          100deg,
          rgba(24, 18, 8, 0) 26%,
          rgba(24, 18, 8, 0.28) 52%,
          rgba(22, 16, 7, 0.72) 82%
        );
      }

      .cf-gate-in {
        position: relative;
        text-align: center;
        font-family: var(--cf-ui);
        color: #f7f0e0;
        /* hard right: the poster is a two-column composition \u2014 building
           in one half, wordmark in the other \u2014 and the wordmark drifting
           toward the middle closes the gap that makes it one */
        margin-right: clamp(34px, 7vw, 132px);
      }

      /* the museum frame: hairline, inset like a mat, above the scene
         and under the type */
      .cf-gate-frame {
        position: absolute;
        inset: clamp(14px, 2.4vw, 30px);
        border: 1px solid rgba(247, 240, 224, 0.34);
        pointer-events: none;
        animation: cf-mg-fade 1200ms ease-out both;
      }

      /* the spine: vertical Japanese down the inside of the frame */
      .cf-gate-vert {
        position: absolute;
        top: 50%;
        left: clamp(30px, 4.6vw, 58px);
        transform: translateY(-50%);
        writing-mode: vertical-rl;
        white-space: nowrap;
        font-family: var(--cf-ui);
        font-weight: 600;
        font-size: clamp(10px, 0.95vw, 13px);
        letter-spacing: 0.3em;
        color: rgba(247, 240, 224, 0.66);
        animation: cf-mg-fade 900ms ease-out both;
        animation-delay: 2050ms;
      }

      .cf-gate-k {
        position: relative;
        margin: 0;
        font-family: var(--cf-display);
        font-weight: 800;
        font-size: clamp(64px, min(20vh, 15vw), 260px);
        letter-spacing: -0.03em;
        white-space: nowrap;
        line-height: 1.02;
        text-shadow: 0 8px 70px rgba(20, 14, 4, 0.55);
      }

      /* the ghost: the title again, enormous and hollow, standing behind
         itself \u2014 the poster's depth comes from one word at two weights */
      .cf-gate-ghost {
        position: absolute;
        left: 50%;
        top: 44%;
        transform: translate(-50%, -50%) scale(1.9);
        font-size: 1em;
        line-height: 1;
        color: transparent;
        -webkit-text-stroke: 1px rgba(247, 240, 224, 0.2);
        white-space: nowrap;
        pointer-events: none;
        animation: cf-mg-ghost 2400ms ease-out both;
        animation-delay: 700ms;
      }

      @keyframes cf-mg-ghost {
        0% {
          opacity: 0;
          transform: translate(-50%, -50%) scale(2.05);
        }

        100% {
          opacity: 1;
          transform: translate(-50%, -50%) scale(1.9);
        }
      }

      /* the index strip along the foot of the frame */
      .cf-gate-index {
        position: absolute;
        left: clamp(40px, 7vw, 90px);
        right: clamp(40px, 7vw, 90px);
        bottom: clamp(30px, 5.4vh, 56px);
        display: flex;
        flex-wrap: wrap;
        justify-content: center;
        gap: 6px clamp(12px, 2.2vw, 36px);
        margin: 0;
        font-family: var(--cf-ui);
        font-size: clamp(9px, 0.8vw, 11px);
        font-weight: 700;
        letter-spacing: 0.22em;
        color: rgba(247, 240, 224, 0.62);
        animation: cf-mg-fade 900ms ease-out both;
        animation-delay: 2500ms;
      }

      .cf-gate-index span {
        white-space: nowrap;
      }

      .cf-gate-t {
        margin: 10px 0 0;
        font-size: 15px;
        font-weight: 800;
        letter-spacing: 0.5em;
        text-indent: 0.5em;
      }

      .cf-gate-s {
        margin: 6px 0 30px;
        font-size: 12px;
        letter-spacing: 0.14em;
        color: rgba(247, 240, 224, 0.72);
      }

      /* the claim under the subtitle: the display serif, italic, a step
         back in the ink; and under it the four words, tiny and wide */
      .cf-gate-live {
        margin: 14px 0 0;
        font-family: var(--cf-display);
        font-style: italic;
        font-size: clamp(15px, 1.25vw, 20px);
        line-height: 1.4;
        letter-spacing: 0.01em;
        color: rgba(247, 240, 224, 0.78);
        max-width: 40ch;
        text-wrap: balance;
      }

      .cf-gate-live-k {
        margin: 8px 0 22px;
        font-family: var(--cf-ui);
        font-size: 10px;
        letter-spacing: 0.22em;
        text-transform: uppercase;
        color: rgba(247, 240, 224, 0.5);
      }

      .cf-gate-row {
        display: flex;
        gap: 12px;
        justify-content: center;
      }

      .cf-go {
        appearance: none;
        font: inherit;
        font-family: var(--cf-ui);
        font-size: 13px;
        font-weight: 600;
        letter-spacing: 0.14em;
        cursor: pointer;
        padding: 14px 30px;
        border-radius: 999px;
        border: 1px solid #f2e9d2;
        background: #f2e9d2;
        color: #2e2515;
        box-shadow: 0 10px 34px rgba(20, 14, 4, 0.35);
        transition:
          transform 220ms cubic-bezier(0.22, 1, 0.36, 1),
          box-shadow 220ms ease;
      }

      .cf-go:hover {
        transform: translateY(-2px);
        box-shadow: 0 16px 44px rgba(20, 14, 4, 0.42);
      }

      .cf-go:disabled {
        opacity: 0.45;
        cursor: default;
      }

      .cf-go.is-quiet {
        background: transparent;
        color: #f2e9d2;
        border-color: rgba(242, 233, 210, 0.5);
      }

      .cf-go.is-quiet:hover {
        border-color: #f2e9d2;
      }

      /* ---- the title package ---------------------------------------- *
         One motion system for front and back matter, staged like a
         broadcast title: rule, glyphs, mark, sub, seal, controls. All
         CSS \u2014 these screens live outside the score on purpose, since
         both exist precisely when the film is not running. */
      .cf-matter {
        position: relative;
      }

      .cf-mg-rule {
        display: block;
        width: 1px;
        height: 56px;
        margin: 0 auto 18px;
        background: rgba(247, 240, 224, 0.65);
        transform-origin: 50% 0;
        animation: cf-mg-rule 900ms cubic-bezier(0.22, 1, 0.36, 1) both;
      }

      @keyframes cf-mg-rule {
        0% {
          transform: scaleY(0);
        }

        100% {
          transform: scaleY(1);
        }
      }

      .cf-mg-g1,
      .cf-mg-g2 {
        display: inline-block;
        animation: cf-mg-glyph 1300ms cubic-bezier(0.22, 1, 0.36, 1) both;
        animation-delay: 350ms;
      }

      .cf-mg-g2 {
        animation-delay: 650ms;
      }

      @keyframes cf-mg-glyph {
        0% {
          opacity: 0;
          filter: blur(16px);
          transform: translateY(10px);
        }

        100% {
          opacity: 1;
          filter: blur(0);
          transform: translateY(0);
        }
      }

      /* the wordmark tracks IN \u2014 from letterspaced air to its set width,
         the oldest move in broadcast titles because nothing else says
         "this is the name" as quietly */
      .cf-mg-mark {
        white-space: nowrap;
        transform-origin: center;
        animation: cf-mg-track 1400ms cubic-bezier(0.22, 1, 0.36, 1) both;
        animation-delay: 1050ms;
      }

      /* THE WORDMARK NO LONGER RE-MEASURES ITSELF.
         Tracking in from 1.1em added about 250px of laid-out width at the
         first frame \u2014 so on anything but a wide screen the mark started
         wrapped onto two lines and un-wrapped partway through its own
         animation, taking the card under it with it. The same gesture
         reads identically as a scale on the X axis, which is a composited
         transform and reflows nothing. */
      @keyframes cf-mg-track {
        0% {
          opacity: 0;
          transform: scaleX(1.16);
        }

        100% {
          opacity: 1;
          transform: scaleX(1);
        }
      }

      .cf-mg-sub {
        animation: cf-mg-fade 800ms ease-out both;
        animation-delay: 1650ms;
      }

      .cf-mg-row {
        animation: cf-mg-fade 800ms ease-out both;
        animation-delay: 2250ms;
      }

      /* centred as a block AND line by line: the shorthand margin used to
         cancel the auto inline margins, so the column sat at the card's
         left edge with its lines centred inside a box narrower than its
         first line */
      .cf-mg-credits {
        display: flex;
        flex-direction: column;
        align-items: center;
        white-space: nowrap;
        max-width: 88vw;
        gap: 4px;
        margin: 0 auto 22px;
        font-size: 11px;
        letter-spacing: 0.14em;
        color: rgba(247, 240, 224, 0.6);
        animation: cf-mg-fade 900ms ease-out both;
        animation-delay: 2050ms;
      }

      @keyframes cf-mg-fade {
        0% {
          opacity: 0;
          transform: translateY(6px);
        }

        100% {
          opacity: 1;
          transform: translateY(0);
        }
      }

      /* the seal: the lineup's stamp, miniature \u2014 it lands hard and
         late, canted the way a hand cants it */
      /* on the end card the seal belongs IN the card: hung off the right
         edge it floated in the corner of the frame with nothing to sit on */
      .cf-end-in .cf-mg-seal {
        position: static;
        margin: 0 auto 16px;
      }

      /* the open end of the date. A dash at the numeral's own weight is a
         slab as wide as a digit and reads as a fifth figure. */
      .cf-end-dash {
        font-style: normal;
        font-size: 0.4em;
        font-weight: 600;
        vertical-align: 0.5em;
        margin-left: 0.08em;
        opacity: 0.7;
      }

      /* THE SEAL IS A DISC AND THE WORD SITS ON ITS CENTRE.
         It was a vertical badge with letterspaced Latin running down it,
         and letter-spacing adds its space AFTER the last letter \u2014 so the
         word was always sitting one space above the middle of its own
         box, which is exactly the kind of thing you cannot stop seeing.
         Horizontal, tracked from the centre (text-indent pays the
         trailing space back), on a round stamp. */
      .cf-mg-seal {
        position: absolute;
        top: 4px;
        right: -76px;
        display: grid;
        place-items: center;
        width: 64px;
        height: 64px;
        font-family: var(--cf-ui);
        font-weight: 700;
        font-size: 15px;
        letter-spacing: 0.12em;
        text-indent: 0.12em;
        text-transform: uppercase;
        color: #f7f0e0;
        background: var(--cf-mark);
        border-radius: 50%;
        animation: cf-mg-seal 500ms cubic-bezier(0.16, 1.2, 0.3, 1) both;
        animation-delay: 1900ms;
      }

      @keyframes cf-mg-seal {
        0% {
          opacity: 0;
          transform: rotate(-4deg) scale(1.6);
        }

        30% {
          opacity: 1;
          transform: rotate(-4deg) scale(0.97);
        }

        100% {
          opacity: 0.94;
          transform: rotate(-4deg) scale(1);
        }
      }

      /* ---- the end card ---------------------------------------------- */
      .cf-end {
        position: absolute;
        inset: 0;
        z-index: 6;
        display: flex;
        align-items: center;
        justify-content: center;
        background: rgba(28, 22, 10, 0.58);
        backdrop-filter: blur(1.5px);
      }

      .cf-end-in {
        text-align: center;
        font-family: var(--cf-ui);
        color: #f7f0e0;
      }

      .cf-end-k {
        margin: 0;
        font-family: var(--cf-display);
        font-weight: 800;
        /* '1882 \u2014' is six characters, not four: at 19vw it was six times
           the viewport wide and it set the width of the whole card */
        font-size: clamp(44px, min(15vh, 9vw), 150px);
        letter-spacing: -0.03em;
        white-space: nowrap;
        line-height: 1;
        text-shadow: 0 6px 60px rgba(20, 14, 4, 0.55);
      }

      .cf-end-t {
        margin: 12px 0 0;
        font-size: 14px;
        font-weight: 800;
        letter-spacing: 0.5em;
        text-indent: 0.5em;
      }

      .cf-end-s {
        margin: 6px 0 26px;
        font-size: 12px;
        letter-spacing: 0.14em;
        color: rgba(247, 240, 224, 0.7);
      }

      /* ---- the stamp -------------------------------------------------- *
         A hanko, not a title: it strikes, settles at once, and is simply
         replaced by the next. Seal-red on purpose \u2014 it shares the
         annotation's ink because it IS an annotation, pressed over each
         tower as the lineup calls the roll. */
      .cf-stamp {
        position: absolute;
        inset: 0;
        z-index: 3;
        display: flex;
        align-items: center;
        justify-content: center;
        margin: 0;
        pointer-events: none;
        font-family: var(--cf-display);
        font-weight: 700;
        font-size: min(24vh, 16vw);
        letter-spacing: 0.04em;
        color: var(--cf-mark);
        mix-blend-mode: multiply;
        animation: cf-stamp 700ms cubic-bezier(0.16, 1.3, 0.3, 1) both;
      }

      @keyframes cf-stamp {
        0% {
          opacity: 0;
          transform: rotate(-2.5deg) scale(1.5);
        }

        16% {
          opacity: 0.92;
          transform: rotate(-2.5deg) scale(0.99);
        }

        100% {
          opacity: 0.88;
          transform: rotate(-2.5deg) scale(1);
        }
      }

      /* the app's own chrome, gone: this route is a frame, not a page */
      body.cf-film .topbar,
      body.cf-film .footer {
        display: none;
      }

      /* A ROMAN WORD IS NOT TWO GLYPHS.
         The block was cut for a two-character CJK setting, where the type
         size and the column width have nothing to do with each other. A
         Latin word's width IS its letter count, so 'Evangelistes' set at
         the size that suited 'Obra' runs off the frame \u2014 and a word that
         wraps to two lines lands the whole plate at a different height.
         So: never wrap, and take the size from the count the plane
         already carries (--cf-glyphs), capped by the design size. 0.56em
         is about the average advance of this face. */
      .cf-kanji.is-latin {
        font-family: var(--cf-display);
        font-weight: 800;
        text-transform: uppercase;
        color: var(--cf-chap);
        writing-mode: horizontal-tb;
        white-space: nowrap;
        font-size: min(
          clamp(40px, 6.2vw, 104px),
          calc(var(--cf-fit, 42vw) / (var(--cf-glyphs, 4) * 0.56))
        );
        letter-spacing: -0.02em;
        line-height: 0.92;
      }
      .is-title .cf-kanji.is-latin {
        --cf-fit: 46vw;
        font-size: min(
          clamp(52px, 8.6vw, 142px),
          calc(var(--cf-fit) / (var(--cf-glyphs, 4) * 0.56))
        );
      }
      .is-plate .cf-kanji.is-latin {
        --cf-fit: 24vw;
        writing-mode: horizontal-tb;
        font-size: min(
          clamp(34px, 4.8vw, 76px),
          calc(var(--cf-fit) / (var(--cf-glyphs, 4) * 0.56))
        );
        letter-spacing: -0.01em;
        max-width: 26vw;
      }
      .is-point .cf-kanji.is-latin {
        --cf-fit: 32vw;
        font-size: min(
          clamp(36px, 5.2vw, 82px),
          calc(var(--cf-fit) / (var(--cf-glyphs, 4) * 0.56))
        );
      }
    </style>
  `, {
      strictMode: true
    }), this);
  }
};

// dist/film/titles.js
import Component14 from "@glimmer/component";
import { precompileTemplate as precompileTemplate14 } from "@ember/template-compilation";
import { setComponentTemplate as setComponentTemplate14 } from "@ember/component";
var Gate2 = class extends Component14 {
  static {
    setComponentTemplate14(precompileTemplate14('\n    <div class="cf-gate">\n      {{!-- the museum frame: a hairline border drawn just inside the screen,\n      the way a plate is matted --}}\n      <i class="cf-gate-frame" aria-hidden="true"></i>\n      {{yield @film}}\n    </div>\n  ', {
      strictMode: true
    }), this);
  }
};
var EndCard = class extends Component14 {
  static {
    setComponentTemplate14(precompileTemplate14('\n    <Choreo class="cf-end" as |m|>\n      <div class="cf-end-in cf-matter" {{motion id="end" role="card"}}>\n        {{yield @film}}\n      </div>\n      <m.Tween @of={{m.inserted "card"}} @delay={{0.7}} @opacity={{array 0 1}} @y={{array 18 0}} @duration={{0.9}} @ease={{array 0.22 1 0.36 1}} />\n      <m.Tween @of={{m.removed "card"}} @opacity={{array 1 0}} @duration={{0.2}} @ease="easeIn" />\n    </Choreo>\n  ', {
      strictMode: true,
      scope: () => ({
        Choreo,
        motion: MotionModifier,
        array: array6
      })
    }), this);
  }
};
function array6(...items) {
  return items;
}

// dist/film/film.js
import { precompileTemplate as precompileTemplate15 } from "@ember/template-compilation";
import { setComponentTemplate as setComponentTemplate15 } from "@ember/component";
var AWAKE = new URLSearchParams(window.location.search).has("awake");
var HAND_AMP = new URLSearchParams(window.location.search).get("hand") === "0" ? 0 : HAND;
var GRADE_LUM = {
  amber: 1.08,
  chalk: 1.27,
  ink: 1,
  iron: 0.9,
  plate: 1.09
};
var EMPTY_BEAT = {
  cam: {
    dolly: 1,
    lookY: 0,
    pitch: 0,
    yaw: 0
  },
  ch: 0,
  id: "",
  mode: "clear",
  ticks: 1
};
var EMPTY_CHAPTER = {
  n: "",
  title: ""
};
var Film = class _Film extends Component15 {
  static {
    decorateFieldV2(this.prototype, "graph", [tracked4], function() {
      return null;
    });
  }
  #graph = (initializeDeferredDecorator(this, "graph"), void 0);
  /* ---- what the film was handed ------------------------------------ */
  /**
  * THE GRAPH, compiled. A film written as `f.Spine` / `f.Chapter` /
  * `f.Shot` in the default block compiles to the same rows a table would
  * hand in (`graph/compile.ts`); the table arguments, when given, win.
  */
  /**
  * DESK PATCHES, keyed by beat id. The graph stays the durable document;
  * this is the live overlay a director's desk writes. `overlayRev` is the
  * tracked cell — the Map itself is not.
  */
  overlay = /* @__PURE__ */ new Map();
  static {
    decorateFieldV2(this.prototype, "overlayRev", [tracked4], function() {
      return 0;
    });
  }
  #overlayRev = (initializeDeferredDecorator(this, "overlayRev"), void 0);
  static {
    decorateFieldV2(this.prototype, "editStamp", [tracked4], function() {
      return 0;
    });
  }
  #editStamp = (initializeDeferredDecorator(this, "editStamp"), void 0);
  /** an edited score needs a fresh sequence name, same as a re-cut */
  takeGraph = (graph) => {
    this.graph = graph;
    this.publishSchedule();
  };
  static {
    decorateFieldV2(this.prototype, "picture", [tracked4], function() {
      return null;
    });
  }
  #picture = (initializeDeferredDecorator(this, "picture"), void 0);
  takePicture = (spec) => {
    this.picture = spec;
  };
  get assets() {
    return this.picture?.assets ?? "";
  }
  /**
  * THE LENS. A 3D picture takes an orbit in world units; a 2D one (a
  * region) takes a frame in fractions of its stage — the same fields,
  * read differently. Everything the film ADDS to a pose on its own
  * account (the poster's circuit, the lean, the breath) has to be said
  * in the lens's units, or a two-degree drift becomes a lurch across
  * half the stage.
  */
  get lens2d() {
    return this.picture?.lens === "2d";
  }
  /** a picture that is a region in this document answers the port itself: no frame, no page */
  get regionPort() {
    return this.picture?.port;
  }
  get standing() {
    return this.picture?.standing ?? 0;
  }
  get frameTitle() {
    return this.picture?.title ?? this.args.name;
  }
  /**
  * THE WHOLE SHOT LIST, and there is only one place it comes from: the
  * score in the default block, compiled. The film used to take a
  * `Beat[]` as an argument as well, which is how both films were fed
  * until Phase 2 migrated them; the table path is gone now that nothing
  * hands one in, and the graph is the only way to write a film.
  */
  get all() {
    void this.overlayRev;
    const base = this.graph?.beats ?? [];
    return frameBeats(applyOverlay(base, this.overlay), this.picture?.port);
  }
  get chapters() {
    return this.graph?.chapters ?? [];
  }
  get voSecs() {
    return this.graph?.voSecs ?? {};
  }
  get voGain() {
    return this.args.voGain ?? this.graph?.voGain ?? {};
  }
  get grades() {
    return this.picture?.grades ?? {};
  }
  get lookFx() {
    return this.picture?.lookFx ?? {};
  }
  get lutAmount() {
    return this.picture?.lutAmount ?? 0.52;
  }
  get defaultJoin() {
    return this.args.join ?? this.graph?.defaultJoin ?? "dip";
  }
  /** the cue table and camera path for the (overlaid) shot list */
  get filmSchedule() {
    return schedule3(this.all, this.chapters, this.defaultJoin);
  }
  /** the schedule as a picture is told it: the shots, and where every line is spoken */
  get pictureSchedule() {
    const s = this.filmSchedule;
    return {
      beats: s.beats,
      total: s.total,
      voice: this.all.flatMap((b, i) => b.vo ? [{
        at: this.beatStart(i),
        id: b.id,
        read: this.voSecs[b.id] ?? b.ticks * TICK * 0.66
      }] : [])
    };
  }
  publishSchedule() {
    this.film?.schedule?.(this.pictureSchedule);
    this.args.onSchedule?.({
      beats: this.all,
      chapters: this.chapters,
      overlay: [...this.overlay.keys()],
      schedule: this.filmSchedule
    });
  }
  /**
  * MERGE A DESK PATCH onto one compiled row, rebuild the spline, and
  * stand the playhead at the same film second. Successive patches on
  * the same id accumulate (`cam.dolly` then `cam.yaw` keeps both).
  */
  patch = (id2, partial) => {
    const hold = this.t;
    const prev = this.overlay.get(id2) ?? {};
    this.overlay.set(id2, mergePatch(prev, partial));
    this.overlayRev += 1;
    this.editStamp += 1;
    this.publishSchedule();
    requestAnimationFrame(() => {
      this.seek(hold);
    });
  };
  clearPatch = (id2) => {
    const hold = this.t;
    if (id2 === void 0) {
      this.overlay.clear();
    } else if (!this.overlay.delete(id2)) {
      return;
    }
    this.overlayRev += 1;
    this.editStamp += 1;
    this.publishSchedule();
    requestAnimationFrame(() => {
      this.seek(hold);
    });
  };
  /**
  * WHERE THIS SEAM IS PLAYED. A seam the PICTURE declares by name is
  * played in its glass with that name; the three the film knows how to
  * mix are played there under the film's own law; everything else is an
  * overlay in this document. The name is the only thing that decides,
  * which is what makes the vocabulary open: a picture that declares
  * `ridged-burn` gets `<f.Join @presentation="ridged-burn" />` for free,
  * and the film learns nothing about it but its length.
  */
  glassFor(join4) {
    if (!this.film?.seam || !this.film.freeze) {
      return null;
    }
    if (this.picture?.seams?.includes(join4)) {
      return {
        name: join4
      };
    }
    return inGlass(join4) ? {} : null;
  }
  /** how deep a seam goes when nothing says: the film's own default */
  get defaultOver() {
    return this.args.over ?? this.graph?.defaultOver ?? "picture";
  }
  /**
  * HOW DEEP THIS BEAT'S SEAM GOES. The row says, or the presentation
  * says, or the film does. A seam that covers the furniture is always a
  * seam with a still in the DOM: the picture's own glass is inside the
  * canvas and cannot cover anything outside it.
  */
  overOf(beat) {
    const join4 = beat.join ?? this.defaultJoin;
    return beat.over ?? this.presentations[join4]?.over ?? this.defaultOver;
  }
  /** every seam the film can play: its own twelve, and any the score brought */
  get presentations() {
    const brought = this.graph?.presentations ?? {};
    const out = {
      ...PRESENTATIONS
    };
    for (const [name, p] of Object.entries(brought)) {
      out[name] = {
        ...out[name],
        component: p.component ?? out[name]?.component,
        over: p.over ?? out[name]?.over,
        secs: p.secs,
        still: p.component ? true : out[name]?.still ?? false
      };
    }
    return out;
  }
  /** seconds a seam holds the picture; nothing, for one the film does not know */
  secsOf(join4) {
    return join4 ? this.presentations[join4]?.secs ?? 0 : 0;
  }
  /** does the seam paint a still of the outgoing frame over the incoming one */
  holdsStill(join4) {
    return !!join4 && !!this.presentations[join4]?.still;
  }
  /** how much of a frosted city a film frame can carry */
  get cityGlass() {
    return this.picture?.cityGlass ?? 0.16;
  }
  /** the rig's mid-height: `lookY` is world height minus this */
  get rigMid() {
    return this.picture?.rigMid ?? 6.6;
  }
  /** how much the passing cloud thickens the air */
  get cloudHaze() {
    return this.picture?.cloudHaze ?? 0.09;
  }
  /** the face type in the world is set in; a film that names none of it
  *  leaves the page's own */
  get worldFamily() {
    const w = this.picture?.worldType;
    return w ? w.family : 'Archivo, "Helvetica Neue", Helvetica, Arial, sans-serif';
  }
  get worldWeight() {
    const w = this.picture?.worldType;
    return w ? w.weight : 800;
  }
  get worldTrack() {
    return this.picture?.worldType?.track ?? 0.02;
  }
  /** the editorial accent: the film's own, or the scene's palette by day */
  accentFor(dark, scene) {
    const a = this.picture?.accent ?? {
      dark: "#d9b44a",
      light: "#8f6b1f"
    };
    return dark ? a.dark : a.light ?? scene ?? "#8f6b1f";
  }
  /** the film's handles, as the door and the card are given them */
  get handle() {
    return {
      ...VOCABULARY,
      /* a picture yields the adjustments it declares; a region declares
      none, and a score that names one on it gets nothing to render */
      picture: this.picture?.adjustments ?? VOCABULARY.picture,
      beat: this.beat,
      beats: this.all,
      begin: this.begin,
      chapter: this.chapter,
      chapters: this.chapters,
      clearPatch: this.clearPatch,
      clock: this.args.clock,
      cutTo: this.pick,
      exact: this.exact,
      isReady: () => this.ready,
      paused: () => this.paused,
      patch: this.patch,
      preview: this.preview,
      ready: this.ready,
      renderAt: this.renderAt,
      restart: this.restart,
      runtime: this.runtime,
      schedule: this.filmSchedule,
      seek: this.seek,
      time: () => this.t,
      toggle: this.toggle,
      toc: this.toc
    };
  }
  /* ---- THE CLOCK, when the film is exact ---------------------------- *
  * One number, seconds into the whole film. The frame loop advances it
  * while playing; a scrub sets it; everything else is derived from it —
  * the beat in force, the seam in progress, the score's and the type's
  * run times, the pose. Nothing below accumulates.
  * ------------------------------------------------------------------ */
  get exact() {
    return this.args.seek === "exact";
  }
  /** the master clock: seconds into the whole film (exact mode) */
  t = 0;
  /** a seek happened since the last fold: it lands instantly, seam re-made */
  jumped = false;
  /** the score region's context, read every frame for its current run */
  scoreCtx = null;
  scoreRun = null;
  /** the element the seam overlays live in, so their animations can be seeked */
  joinsEl;
  /** where the seam on screen began, film seconds, and how long it plays */
  seamAt = -1;
  seamLen = 0;
  /** the lead whose air has been applied ahead of its beat */
  airedFor = -1;
  /** where the sun was before this beat asked, for a deterministic walk */
  sunFrom = null;
  static {
    decorateFieldV2(this.prototype, "clipKey", [tracked4], function() {
      return "";
    });
  }
  #clipKey = (initializeDeferredDecorator(this, "clipKey"), void 0);
  static {
    decorateFieldV2(this.prototype, "clipState", [tracked4], function() {
      return "absent";
    });
  }
  #clipState = (initializeDeferredDecorator(this, "clipState"), void 0);
  static {
    decorateFieldV2(this.prototype, "clipFreeze", [tracked4], function() {
      return "";
    });
  }
  #clipFreeze = (initializeDeferredDecorator(this, "clipFreeze"), void 0);
  /** the picture read back, for a freeze */
  clipNow = null;
  clipMedia;
  clipEl = modifier9((el) => {
    this.clipMedia = el;
    return () => {
      if (this.clipMedia === el) {
        this.clipMedia = void 0;
      }
    };
  });
  /* clipNow is written every frame and so is not tracked; clipKey is,
   and it changes exactly when clipNow names a different clip — so both
   getters read it, or a second clip renders with the first one's src */
  get clipSrc() {
    void this.clipKey;
    const src = this.clipNow?.spec.src;
    return src ? `${this.assets}${src}` : "";
  }
  get clipSpec() {
    void this.clipKey;
    return this.clipNow?.spec ?? {
      kind: "image"
    };
  }
  /**
  * THE CLIP, EVERY FRAME. Resolve what should be on screen at this film
  * time, land the DOM when that changes (a new window is a new element,
  * so the entrance replays), and drive the media: a playing video is
  * left to run and corrected when it drifts, a paused or scrubbed one
  * is seeked, a held one stands at its out point, a frozen one is left
  * alone. A freeze reads the picture back when its window opens — or,
  * on a seek into it, after the page has been stood at that moment.
  */
  clips(film, filmTime, jumped) {
    const found = resolveClip(this.all, (i) => this.beatStart(i), filmTime, this.absoluteIndex, this.totalSecs);
    const key = found ? `${this.all[found.index].id}` : "";
    const was = this.clipNow;
    this.clipNow = found;
    if (key !== this.clipKey) {
      this.clipKey = key;
      this.clipFreeze = "";
      if (found?.spec.kind === "freeze") {
        if (jumped || found.since > 0.1) {
          this.freezeClipAt(found, filmTime);
        }
        const shot = film.snapshot();
        this.clipFreeze = shot.length > 64 ? shot : "";
      }
    }
    const state = found?.state ?? "absent";
    if (state !== this.clipState) {
      this.clipState = state;
    }
    if (!found || found.spec.kind !== "video") {
      const gone = this.clipMedia;
      if (gone instanceof HTMLVideoElement && gone.volume > 1e-3) {
        gone.volume = Math.max(0, gone.volume - 0.12);
      }
      return;
    }
    const v = this.clipMedia;
    if (!(v instanceof HTMLVideoElement) || found.source === null) {
      return;
    }
    const level = Math.max(0, Math.min(1, found.spec.volume ?? 0));
    if (was?.index !== found.index) {
      v.volume = 0;
    }
    const closing = found.state !== "active" ? 0 : level;
    if (Math.abs(v.volume - closing) > 2e-3) {
      v.volume = v.volume + (closing - v.volume) * 0.28;
    }
    const rate = found.spec.rate ?? 1;
    const live = found.state === "active" && this.playing && this.scrubAt === null && !jumped;
    if (live) {
      if (v.paused) {
        v.currentTime = found.source;
        v.playbackRate = rate;
        void v.play().catch(() => {
        });
      } else if (Math.abs(v.currentTime - found.source) > 0.2) {
        v.currentTime = found.source;
      }
    } else {
      if (!v.paused) {
        v.pause();
      }
      if (Math.abs(v.currentTime - found.source) > 0.04) {
        v.currentTime = found.source;
      }
    }
  }
  /**
  * THE PICTURE AT A MOMENT THAT HAS PASSED. A freeze seeked into needs
  * the frame from its window's head: the score is stood there for one
  * evaluation (the camera step reports the pose), the page is posed and
  * clocked to that moment, and the fold's own time is restored after
  * the read-back.
  */
  freezeClipAt(clip, filmTime) {
    const film = this.film;
    const run = this.scoreCtx?.run ?? null;
    if (!film || !run) {
      return;
    }
    const head = filmTime - clip.since;
    const b = this.all[clip.index];
    const local = Math.min(1, Math.max(0, (head - this.beatStart(clip.index)) / (b.ticks * TICK)));
    run.pause();
    run.time = head;
    const g = this.goal;
    film.pose({
      az: g.yaw * RAD,
      el: g.pitch * RAD,
      fov: null,
      fx: g.fx ?? 0,
      fz: g.fz ?? 0,
      lookY: g.lookY,
      near: null,
      ox: g.ox ?? 0,
      snap: true,
      zoom: g.dolly
    });
    if (Array.isArray(b.build)) {
      film.time(lerp(b.build[0], b.build[1], smooth(Math.min(1, local / (b.buildBy ?? 1)))));
    }
    run.time = this.exact ? this.t : run.time;
  }
  /**
  * FILM SECONDS AT WHICH A BEAT'S OWN SHOT BEGINS. The cues fire one
  * tick after the beat table says, because the pose-in-force seed
  * occupies the spline's first slot — so the windows the exact clock
  * derives carry the same offset, and the picture and the type agree
  * with the cut film to the frame.
  */
  beatStart(i) {
    return beatStart(this.all, i);
  }
  /** the beat in force at a film time */
  indexAt(t) {
    let i = 0;
    while (i + 1 < this.all.length && this.beatStart(i + 1) <= t) {
      i += 1;
    }
    return i;
  }
  /** the score's region, held so its run can be driven by the clock */
  grabScore = modifier9((_el, [ctx]) => {
    this.scoreCtx = ctx;
    return () => {
      if (this.scoreCtx === ctx) {
        this.scoreCtx = null;
      }
    };
  });
  joinsWrap = modifier9((el) => {
    this.joinsEl = el;
    return () => {
      if (this.joinsEl === el) {
        this.joinsEl = void 0;
      }
    };
  });
  /** the score must stand even while paused: a paused exact film is a still */
  get scoreOn() {
    return this.playing || this.exact;
  }
  /**
  * SEEK. In exact mode the clock is set and the next fold lands there;
  * in cut mode the nearest shot's head is re-cut to, which is the only
  * honest seek a chased lens has.
  */
  seek = (seconds) => {
    if (!this.exact) {
      let i = 0;
      while (i + 1 < this.all.length && this.secsBefore(i + 1) <= seconds) {
        i += 1;
      }
      this.cutTo(i);
      return;
    }
    const total = this.totalSecs;
    this.t = Math.max(0, Math.min(total, seconds));
    this.jumped = true;
    this.menu = false;
    if (this.ended && this.t < total) {
      this.ended = false;
      this.idled = false;
      this.film?.idle(false);
    }
    if (this.booted && this.film) {
      this.fold();
    }
  };
  /**
  * A STILL AT A TIME, for a capture worker: pause, seek, run one frame
  * of the loop against a zero step, and give the page two frames to
  * draw it. The same code path as playing there — that is the claim.
  */
  /** a frame is being rendered rather than scrubbed to: seams play */
  rendering = false;
  renderAt = async (seconds) => {
    if (!this.exact) {
      this.seek(seconds);
      return;
    }
    this.playing = false;
    this.rendering = true;
    try {
      this.seek(seconds);
      const now2 = performance.now();
      this.lastTick = now2;
      this.tick(now2);
      await new Promise((r) => requestAnimationFrame(() => r(void 0)));
      await new Promise((r) => requestAnimationFrame(() => r(void 0)));
    } finally {
      this.rendering = false;
    }
  };
  /**
  * THE FOLD (exact mode): the beat in force is the one whose window
  * holds the clock; entering it — forward by playing, or by a seek in
  * either direction — applies it whole, because every beat asserts its
  * complete state and never inherits. A seek that lands inside a seam
  * re-makes the outgoing frame first, so the seam plays from the middle
  * exactly as it would have played into it.
  */
  fold() {
    const film = this.film;
    if (!film) {
      return;
    }
    const t = this.t;
    const i = this.indexAt(t);
    const jumped = this.jumped;
    this.jumped = false;
    film.clock?.(t, jumped);
    const next2 = this.all[i + 1];
    if (next2 && (next2.lead ?? 0) > 0 && t >= this.secsBefore(i + 1) + TICK && this.airedFor !== i + 1) {
      this.airedFor = i + 1;
      this.applyAir(next2, false);
    }
    if (i !== this.beatIndex || jumped) {
      const beat = this.all[i];
      const since = t - this.beatStart(i);
      if (jumped) {
        this.settleAir(i);
        this.airedFor = -1;
        this.freeze = "";
      }
      const join4 = beat.cut || beat.join ? beat.join ?? this.defaultJoin : null;
      const len = this.secsOf(join4 ?? void 0);
      this.seamAt = -1;
      this.seamLen = 0;
      const inSeam = !!join4 && since < len && i > 0 && (!jumped || this.rendering);
      const frozen = false;
      if (inSeam) {
        this.seamAt = this.beatStart(i);
        this.seamLen = len;
      }
      this.beatIndex = i;
      this.applyBeat(beat, jumped, {
        frozen,
        seam: inSeam,
        since
      });
      if (jumped) {
        this.speakAt(beat, since);
      }
    }
    if (this.seamAt >= 0) {
      const ms = Math.max(0, (t - this.seamAt) * 1e3);
      for (const a of this.joinsEl?.getAnimations({
        subtree: true
      }) ?? []) {
        a.pause();
        a.currentTime = ms;
      }
      if (t - this.seamAt > this.seamLen + 0.3 || t < this.seamAt) {
        this.seamAt = -1;
        this.joinKind = "";
      }
    }
    const run = this.scoreCtx?.run ?? null;
    if (run !== this.scoreRun) {
      this.scoreRun = run;
      run?.pause();
    }
    if (run) {
      run.time = t;
    }
    if (t >= this.totalSecs && !this.ended) {
      this.end();
    }
  }
  /** a line, from the middle: what a seek owes the voice */
  speakAt(beat, since) {
    this.hush();
    const own = this.all.indexOf(beat);
    if (!beat.vo && !beat.hush && own > 0) {
      const i = own;
      const at2 = this.beatStart(i) + since;
      for (let j = i - 1; j >= 0; j -= 1) {
        const prior = this.all[j];
        if (prior.hush) {
          break;
        }
        if (prior.vo) {
          const read2 = this.voSecs[prior.id] ?? prior.ticks * TICK * 0.66;
          const into = at2 - this.beatStart(j);
          if (into < read2 - 0.3 && this.sound) {
            this.film?.voice(this.voSrc(prior), this.voGain[prior.id] ?? 1, into);
            return;
          }
          break;
        }
      }
    }
    if (!beat.vo || !this.sound) {
      this.film?.duck(1);
      return;
    }
    const read = this.voSecs[beat.id] ?? beat.ticks * TICK * 0.66;
    if (since < read - 0.3) {
      this.film?.voice(this.voSrc(beat), this.voGain[beat.id] ?? 1, since);
      this.primeNext(beat);
    } else {
      this.film?.duck(1);
    }
  }
  /**
  * THE SEAM'S GATE (`film/seam.ts`). A join's still is a JPEG the
  * browser has not decoded yet on the frame it is handed over, and the
  * lens moves on that frame — so every cut used to show three frames of
  * the incoming shot before the outgoing one was on screen. The gate
  * decodes first and holds the cut; a seam with no still runs at once.
  */
  seam = new Seam();
  /**
  * THE SEAM, EXACT. Every join that carries the outgoing frame carries it
  * as a still in the DOM — the page's own dissolves run on the page's
  * clock and cannot be stood at a time — and the whip, which is the
  * chaser's, becomes a cut. The overlay is then driven by the fold.
  */
  seamExact(film, beat, join4, seam) {
    const wants = seam ? seam.seam : true;
    const glass = wants ? this.glassFor(join4) : null;
    if (glass) {
      if (this.glassKind !== join4) {
        film.freeze?.(true);
        this.glassKind = join4;
        this.glassName = glass.name ?? "";
        this.glassLen = this.secsOf(join4);
        this.glassColor = beat.dipTo ?? "#0d0905";
        this.freeze = "";
        this.joinKind = "";
      }
      if (beat.cut) {
        this.snap(beat.cam);
      }
      return;
    }
    const stills = this.holdsStill(join4);
    let held = this.freeze;
    if (wants && stills && !seam?.frozen) {
      const shot = film.snapshot();
      held = shot.length > 64 ? shot : "";
    }
    if (!wants) {
      held = "";
      this.freeze = "";
    }
    if (held) {
      film.freeze?.(true);
    }
    this.seam.hold(held, () => {
      film.freeze?.(false);
      this.seamPlay(film, beat, join4, wants, held);
    });
  }
  /** the seam itself: the still on screen, the lens on the incoming shot */
  seamPlay(film, beat, join4, wants, held) {
    this.freeze = held;
    if (beat.cut || join4 === "wipe" || join4 === "whip") {
      this.snap(beat.cam);
    }
    if (!wants) {
      return;
    }
    const deep = this.overOf(beat);
    switch (join4) {
      case "cut":
      case "whip":
        break;
      case "dip":
        this.dipColor = beat.dipTo ?? "#0d0905";
        this.play("dip", deep);
        break;
      case "flash":
        this.play("flash", deep);
        break;
      case "sweep":
        this.lightSweep(film, beat);
        break;
      case "defocus":
        if (this.freeze) {
          this.play("defocus", deep);
        }
        break;
      case "iris": {
        if (!this.freeze) {
          break;
        }
        const v = film.view();
        const p = beat.to ? film.project(...beat.to) : void 0;
        const cx = p ? Math.max(12, Math.min(88, p.x / v.w * 100)) : 50;
        const cy = p ? Math.max(12, Math.min(88, p.y / v.h * 100)) : 50;
        this.irisAt = `--ix:${cx.toFixed(1)}%;--iy:${cy.toFixed(1)}%`;
        this.play("iris", deep);
        break;
      }
      default:
        if (this.freeze) {
          this.play(join4, deep);
        }
    }
  }
  /** the last cue has run: hold the pose, settle the music, offer the card */
  end() {
    this.playing = false;
    this.ended = true;
    this.film?.voiceStop(1e3);
    if (this.film?.outro) {
      this.film.outro(4200);
    } else {
      this.film?.duck(0.35);
    }
  }
  static {
    decorateFieldV2(this.prototype, "beatIndex", [tracked4], function() {
      return 0;
    });
  }
  #beatIndex = (initializeDeferredDecorator(this, "beatIndex"), void 0);
  static {
    decorateFieldV2(this.prototype, "playing", [tracked4], function() {
      return true;
    });
  }
  #playing = (initializeDeferredDecorator(this, "playing"), void 0);
  static {
    decorateFieldV2(this.prototype, "lap", [tracked4], function() {
      return 0;
    });
  }
  #lap = (initializeDeferredDecorator(this, "lap"), void 0);
  static {
    decorateFieldV2(this.prototype, "booted", [tracked4], function() {
      return false;
    });
  }
  #booted = (initializeDeferredDecorator(this, "booted"), void 0);
  static {
    decorateFieldV2(this.prototype, "joinKind", [tracked4], function() {
      return "";
    });
  }
  #joinKind = (initializeDeferredDecorator(this, "joinKind"), void 0);
  static {
    decorateFieldV2(this.prototype, "joinStamp", [tracked4], function() {
      return 0;
    });
  }
  #joinStamp = (initializeDeferredDecorator(this, "joinStamp"), void 0);
  static {
    decorateFieldV2(this.prototype, "joinOver", [tracked4], function() {
      return false;
    });
  }
  #joinOver = (initializeDeferredDecorator(this, "joinOver"), void 0);
  /** the seam on screen covers the furniture, not only the picture */
  overTimer = 0;
  /**
  * THE SEAM IN THE GLASS. Its kind, how long it has and the colour it
  * passes through — and `reveal`, how much of the incoming frame is NOT
  * covered by it, which is the film's other half: the type, the stamp
  * and the inserts wear it, so a caption is uncovered by the same
  * gesture that uncovers the picture.
  */
  glassKind = "";
  /** the picture's own name for it, when the picture declared this seam */
  glassName = "";
  glassLen = 0;
  glassColor = "";
  reveal = 1;
  static {
    decorateFieldV2(this.prototype, "freeze", [tracked4], function() {
      return "";
    });
  }
  #freeze = (initializeDeferredDecorator(this, "freeze"), void 0);
  static {
    decorateFieldV2(this.prototype, "dipColor", [tracked4], function() {
      return "#0d0905";
    });
  }
  #dipColor = (initializeDeferredDecorator(this, "dipColor"), void 0);
  static {
    decorateFieldV2(this.prototype, "irisAt", [tracked4], function() {
      return "";
    });
  }
  #irisAt = (initializeDeferredDecorator(this, "irisAt"), void 0);
  static {
    decorateFieldV2(this.prototype, "fault", [tracked4], function() {
      return "";
    });
  }
  #fault = (initializeDeferredDecorator(this, "fault"), void 0);
  /** dev beacon: the first uncaught error, worn on the sleeve */
  /**
  * THE SEAM, DRIVEN. Half of it is the picture, which is handed two
  * numbers and composites them in light; half is the furniture, which
  * wears what is left over. Both come from one progress, and that
  * progress is a function of the clock — so a seek through a seam needs
  * nothing stood at a time, which is what the DOM overlay always did.
  */
  /** take a driven seam off: the picture back to live, the furniture whole */
  endSeam() {
    if (!this.glassKind) {
      return;
    }
    this.glassKind = "";
    this.glassName = "";
    this.reveal = 1;
    this.film?.seam?.(null);
  }
  driveSeam(film, t) {
    if (!this.glassKind) {
      return;
    }
    const len = Math.max(1e-3, this.glassLen);
    const p = this.exact ? this.seamAt >= 0 ? (t - this.seamAt) / len : 1 : (performance.now() - this.beatAt) / 1e3 / len;
    if (p >= 1) {
      this.endSeam();
      return;
    }
    if (this.glassName) {
      film.seam?.({
        mix: 0,
        name: this.glassName,
        p,
        veil: 0
      });
      this.reveal = p;
      return;
    }
    const {
      mix: mix2,
      veil
    } = seamShape(this.glassKind, p);
    film.seam?.({
      color: this.glassColor,
      mix: mix2,
      p,
      veil
    });
    this.reveal = 1 - Math.max(mix2, veil);
  }
  /**
  * Run a seam's overlay: a new element per cut, from its own first
  * frame. A seam played `everything` is lifted above the type, the
  * insert and the clip for as long as it runs, and put back after — an
  * empty layer left standing over the furniture would swallow the next
  * shot's pointer events, and there is no event for a CSS animation the
  * film did not start.
  */
  play(kind, over = "picture") {
    this.joinKind = kind;
    this.joinStamp += 1;
    this.joinOver = over === "everything";
    window.clearTimeout(this.overTimer);
    if (this.joinOver) {
      const stamp = this.joinStamp;
      this.overTimer = window.setTimeout(() => {
        if (this.joinStamp === stamp) {
          this.joinOver = false;
        }
      }, this.secsOf(kind) * 1e3 + 80);
    }
  }
  static {
    decorateFieldV2(this.prototype, "ended", [tracked4], function() {
      return false;
    });
  }
  #ended = (initializeDeferredDecorator(this, "ended"), void 0);
  static {
    decorateFieldV2(this.prototype, "yearNow", [tracked4], function() {
      return 1882;
    });
  }
  #yearNow = (initializeDeferredDecorator(this, "yearNow"), void 0);
  /**
  * THE YEAR IS THE SUBJECT. A film whose whole argument is that one
  * building took a hundred and forty-four years cannot leave the audience
  * to infer the date from the state of the scaffolding: the year is on
  * screen, and it is on a line from the first stone to the present, so
  * 1954 is not a number but a POSITION — two thirds along a rule that
  * still has a third to run.
  */
  yearSent = 0;
  /** whether the announced year is currently seated in the scene */
  stampOn = false;
  /** the page has been told the picture is static — see the frame loop */
  idled = false;
  gradeSent = "";
  rakeSent = NaN;
  rakeDeg = 35;
  /** which beat's lightning cue has fired (reset on every beat change) */
  struck = "";
  /** which of the beat's hours (Beat.hours) is in force; -1 between beats */
  hourStep = -1;
  /** the next grade goes to the glass without its ease (a still-join) */
  gradeSnap = false;
  /** the last stock sent to the glass, by name; undefined before the first */
  lutSent = void 0;
  /** the last hour a beat named, so the night can be known without naming it again */
  hourNow = 0;
  /** the scrub track's width in px, kept by a ResizeObserver */
  trackW = 0;
  trackRO;
  /** the chapter fractions the bar is drawn with, computed once */
  segFr;
  trackWrap = modifier9((el) => {
    this.trackW = el.clientWidth;
    this.trackRO = new ResizeObserver(() => {
      this.trackW = el.clientWidth;
    });
    this.trackRO.observe(el);
    return () => {
      this.trackRO?.disconnect();
      this.trackRO = void 0;
    };
  });
  /**
  * THE KNOB IS THE FILL'S END. The bar is chapters with a gap between
  * them, so the playhead's position is not linear in the playhead's
  * value — a second formula for the knob drifts from the fill inside
  * every segment. This is the one formula: the same fractions the fill
  * uses, over the measured track, with the gaps added back.
  */
  headPx(prog) {
    const segs = this.segFr ??= this.playbar.map((c) => {
      const m = /--s0:([\d.]+);--sl:([\d.]+)/.exec(c.style);
      return {
        s0: +m[1],
        sl: +m[2]
      };
    });
    const gap = 2;
    const usable = this.trackW - gap * (segs.length - 1);
    let i = segs.findIndex((s2, n) => prog < s2.s0 + s2.sl || n === segs.length - 1);
    if (i < 0) {
      i = segs.length - 1;
    }
    const s = segs[i];
    const f = Math.max(0, Math.min(1, (prog - s.s0) / s.sl));
    return (s.s0 + f * s.sl) * usable + i * gap;
  }
  static {
    decorateFieldV2(this.prototype, "cycleStep", [tracked4], function() {
      return -1;
    });
  }
  #cycleStep = (initializeDeferredDecorator(this, "cycleStep"), void 0);
  film;
  static {
    decorateFieldV2(this.prototype, "washInGlass", [tracked4], function() {
      return false;
    });
  }
  #washInGlass = (initializeDeferredDecorator(this, "washInGlass"), void 0);
  static {
    decorateFieldV2(this.prototype, "cloudInGlass", [tracked4], function() {
      return false;
    });
  }
  #cloudInGlass = (initializeDeferredDecorator(this, "cloudInGlass"), void 0);
  static {
    decorateFieldV2(this.prototype, "dimInGlass", [tracked4], function() {
      return false;
    });
  }
  #dimInGlass = (initializeDeferredDecorator(this, "dimInGlass"), void 0);
  /** the palette's paper, as `wear` last read it, for the wash */
  paperNow = "";
  /** the last wash the picture was told about: mode and paper, told on change */
  washSent = "";
  frameEl;
  lineEl;
  dotEl;
  tetherEl;
  dim;
  /** the dim's own value, chased rather than cut so it never snaps on */
  dimNow = 0;
  plateEl;
  rowEls = [];
  raf = 0;
  lastTick = 0;
  /** when the current beat was entered, for the clocks it owns */
  beatAt = 0;
  /** where the beat's sky word was planted, in world azimuth */
  skyAz = 0;
  /** the azimuth the mark word is planted on, behind the building */
  markAz = 0;
  /** a sideways nudge in world units, for a word too short to centre */
  markOff = 0;
  /** the height the word rises FROM — set when it actually arrives */
  markFrom = 2.6;
  markSeated = false;
  /** the last pose actually pushed — the final smoothing stage */
  sent;
  /** the light in force, and the light the beat asked for */
  sunNow = null;
  sunGoal = null;
  static {
    decorateFieldV2(this.prototype, "idle", [tracked4], function() {
      return false;
    });
  }
  #idle = (initializeDeferredDecorator(this, "idle"), void 0);
  static {
    decorateFieldV2(this.prototype, "scrubAt", [tracked4], function() {
      return null;
    });
  }
  #scrubAt = (initializeDeferredDecorator(this, "scrubAt"), void 0);
  static {
    decorateFieldV2(this.prototype, "hoverAt", [tracked4], function() {
      return null;
    });
  }
  #hoverAt = (initializeDeferredDecorator(this, "hoverAt"), void 0);
  static {
    decorateFieldV2(this.prototype, "vol", [tracked4], function() {
      return _Film.savedVol();
    });
  }
  #vol = (initializeDeferredDecorator(this, "vol"), void 0);
  static {
    decorateFieldV2(this.prototype, "burst", [tracked4], function() {
      return "";
    });
  }
  #burst = (initializeDeferredDecorator(this, "burst"), void 0);
  static {
    decorateFieldV2(this.prototype, "paused", [tracked4], function() {
      return false;
    });
  }
  #paused = (initializeDeferredDecorator(this, "paused"), void 0);
  /** the viewer's pause: the run, the page and the beat clock all hold */
  pausedAt = 0;
  /** the lap whose head beat the cut itself already applied */
  primedLap = -1;
  /** the bar's own element, for the slider's live value */
  scrubEl;
  shownPct = -1;
  static {
    decorateFieldV2(this.prototype, "clock", [tracked4], function() {
      return "0:00";
    });
  }
  #clock = (initializeDeferredDecorator(this, "clock"), void 0);
  static {
    decorateFieldV2(this.prototype, "full", [tracked4], function() {
      return false;
    });
  }
  #full = (initializeDeferredDecorator(this, "full"), void 0);
  idleTimer = 0;
  shownSec = -1;
  /** the whole film, in seconds, leads included */
  get totalSecs() {
    return totalSecs(this.all);
  }
  secsBefore(index) {
    return secsBefore(this.all, index);
  }
  /** one segment per chapter, sized and placed in whole-film fractions */
  get playbar() {
    const total = this.totalSecs;
    return this.chapterHeads.map((head, i) => {
      const end = this.chapterHeads[i + 1] ?? this.all.length;
      const ch = this.chapters[this.all[head].ch] ?? this.chapters[0];
      const s0 = this.secsBefore(head) / total;
      const sl = (this.secsBefore(end) - this.secsBefore(head)) / total;
      return {
        head,
        n: ch.n,
        style: `flex:${sl};--s0:${s0.toFixed(5)};--sl:${sl.toFixed(5)}`,
        title: ch.title
      };
    });
  }
  static mmss(s) {
    const m = Math.floor(Math.max(0, s) / 60);
    return `${m}:${String(Math.floor(Math.max(0, s) % 60)).padStart(2, "0")}`;
  }
  get duration() {
    return _Film.mmss(this.totalSecs);
  }
  /**
  * What the hand is pointing at — resting on the bar or dragging it:
  * the chapter under it and the time, on two lines, the way every
  * player's hover bubble does. A drag wins over a hover.
  */
  get tip() {
    const at2 = this.scrubAt ?? this.hoverAt;
    if (at2 === null) {
      return null;
    }
    const want = at2 * this.totalSecs;
    let i = 0;
    while (i + 1 < this.all.length && this.secsBefore(i + 1) <= want) {
      i += 1;
    }
    const ch = this.chapters[this.all[i].ch] ?? this.chapters[0];
    return {
      ch: `${ch.n} ${ch.title}`,
      t: _Film.mmss(want)
    };
  }
  /** rolling AND not held by the viewer: what the play button shows */
  get live() {
    return this.playing && !this.paused;
  }
  /** the fader's setting, as it was left last time — one setting for
  *  every film, the way a viewer's volume is theirs and not the film's */
  static savedVol() {
    try {
      const v = Number(window.localStorage.getItem("cf-vol"));
      return Number.isFinite(v) && v > 0 && v <= 1 ? v : 1;
    } catch {
      return 1;
    }
  }
  /** sound on, and the fader up: the speaker glyph's three states */
  get loud() {
    if (!this.sound || this.vol <= 0) {
      return "off";
    }
    return this.vol < 0.5 ? "low" : "high";
  }
  get volStyle() {
    return `--cf-vol:${this.vol.toFixed(2)}`;
  }
  /**
  * THE FADER. Dragging it up while muted unmutes, because that is what
  * the hand means; the value is the page's master gain, under the mix
  * and the mute, and it is remembered for the next visit.
  */
  fade = (e) => {
    const v = Number(e.target.value);
    this.vol = v;
    this.film?.volume?.(v);
    try {
      window.localStorage.setItem("cf-vol", v.toFixed(2));
    } catch {
    }
    if (v > 0 && !this.sound) {
      this.hear();
    }
  };
  /** the glyph that flashes in the middle of the picture on play/pause */
  pop(kind) {
    if (this.gate || this.ended) {
      return;
    }
    this.burst = "";
    requestAnimationFrame(() => {
      this.burst = kind;
    });
  }
  burstDone = () => {
    this.burst = "";
  };
  /**
  * A tap on the picture is play/pause and two taps are full screen —
  * the grammar of every player since the first one. The controls, the
  * door, the end card, the rail and the menu keep their own clicks.
  */
  static onGlass(e) {
    const t = e.target;
    return !t?.closest("button, a, input, .cf-player, .cf-menu, .cf-gate, .cf-rail");
  }
  tap = (e) => {
    if (this.gate || this.ended || this.menu || !_Film.onGlass(e)) {
      return;
    }
    this.toggle();
  };
  tapTwice = (e) => {
    if (this.gate || this.ended || this.menu || !_Film.onGlass(e)) {
      return;
    }
    this.screen();
  };
  /** the bar's own element, for the slider's live value */
  slider = modifier9((el) => {
    this.scrubEl = el;
    return () => {
      this.scrubEl = void 0;
    };
  });
  wake = () => {
    if (this.idle) {
      this.idle = false;
    }
    window.clearTimeout(this.idleTimer);
    this.idleTimer = window.setTimeout(() => {
      if (this.scrubAt === null && !this.menu && this.live) {
        this.idle = true;
      }
    }, 2600);
  };
  scrubFrom(e) {
    const el = e.currentTarget.getBoundingClientRect();
    return Math.max(0, Math.min(1, (e.clientX - el.left) / el.width));
  }
  /**
  * The bubble and the ghost fill follow the pointer, not the playhead:
  * the bubble's x in pixels (held off the edges so it never clips) and
  * the hover fraction, both as properties, both without a re-render.
  */
  point(e) {
    const r = e.currentTarget.getBoundingClientRect();
    const x = Math.max(0, Math.min(r.width, e.clientX - r.left));
    const at2 = r.width > 0 ? x / r.width : 0;
    const pad = Math.min(56, r.width / 2);
    const st = this.pageEl?.style;
    st?.setProperty("--cf-tipx", Math.max(pad, Math.min(r.width - pad, x)).toFixed(1));
    st?.setProperty("--cf-hov", at2.toFixed(5));
    return at2;
  }
  scrubDown = (e) => {
    e.currentTarget.setPointerCapture(e.pointerId);
    this.scrubAt = this.point(e);
  };
  scrubMove = (e) => {
    const at2 = this.point(e);
    if (this.scrubAt !== null) {
      this.scrubAt = at2;
      if (this.exact) {
        this.seek(this.barSecs(this.scrubAt));
      }
    } else if (e.pointerType !== "touch") {
      this.hoverAt = at2;
    }
  };
  scrubLeave = () => {
    this.hoverAt = null;
    this.pageEl?.style.setProperty("--cf-hov", "0");
  };
  /**
  * THE PLAYHEAD SNAPS TO A SHOT, because this film cannot seek: the
  * lens is an integrator and a run dropped into its own middle arrives
  * with the wrong velocity (docs/choreo-splices.md). So the drag reads
  * as time, the label names the shot under the hand, and the release
  * RE-CUTS from that shot's head — which is the same edit the chapter
  * buttons and the arrow keys make.
  */
  /**
  * A HAND ON THE BAR NEVER LANDS ON THE CARD. The bar's right edge is
  * the film's last second, and a click there — or a drag that ran off
  * the end — seeks to the total, which is the ending itself: the card
  * came up under a hand that wanted the last shot. The bar stops two
  * seconds short; the ending is reached by playing to it.
  */
  barSecs(at2) {
    return Math.min(at2 * this.totalSecs, Math.max(0, this.totalSecs - 2));
  }
  scrubUp = (e) => {
    const at2 = this.scrubAt ?? this.scrubFrom(e);
    this.scrubAt = null;
    this.hoverAt = null;
    this.pageEl?.style.setProperty("--cf-hov", "0");
    this.seek(this.barSecs(at2));
  };
  screen = () => {
    const el = this.pageEl ?? this.frameEl;
    if (!el) {
      return;
    }
    if (document.fullscreenElement) {
      void document.exitFullscreen();
    } else {
      void el.requestFullscreen?.();
    }
  };
  fullChange = () => {
    this.full = !!document.fullscreenElement;
  };
  /**
  * THE POINTER MOVES THE WORLD A LITTLE.
  *
  * A film that cannot be touched is a video, and the whole argument
  * here is that this is a scene. So the cursor gets a few degrees of
  * lean: the lens takes a fraction of it (real parallax — the building
  * and the hills separate) and the type planes take more of it in the
  * other direction, each layer by its own depth. It is small enough to
  * be felt rather than played with, and damped, so it never fights the
  * shot the score is composing.
  */
  lean = {
    x: 0,
    y: 0
  };
  leanTo = {
    x: 0,
    y: 0
  };
  aim = (e) => {
    const el = this.pageEl ?? this.frameEl;
    if (!el) {
      return;
    }
    const r = el.getBoundingClientRect();
    this.leanTo.x = Math.max(-1, Math.min(1, (e.clientX - r.left) / r.width * 2 - 1));
    this.leanTo.y = Math.max(-1, Math.min(1, (e.clientY - r.top) / r.height * 2 - 1));
  };
  /** the haze the beat asked for — the weather drift breathes around it */
  hazeBase = null;
  /* the score's goal, and the two stages that chase it */
  goal = {
    ...(this.all[0] ?? EMPTY_BEAT).cam
  };
  mid = {
    ...(this.all[0] ?? EMPTY_BEAT).cam
  };
  midV = {
    dolly: 0,
    fx: 0,
    fz: 0,
    lookY: 0,
    ox: 0,
    pitch: 0,
    yaw: 0
  };
  now = {
    ...(this.all[0] ?? EMPTY_BEAT).cam
  };
  nowV = {
    dolly: 0,
    fx: 0,
    fz: 0,
    lookY: 0,
    ox: 0,
    pitch: 0,
    yaw: 0
  };
  /** the world-layer plane's own fade, so a chapter's type breathes in */
  skyOn = 0;
  /**
  * THE SKY WORD'S OPACITY AS ACTUALLY SENT — not the ramp above.
  *
  * `skyOn` only says a word is WANTED; what the word is actually wearing
  * is that ramp times the beat's own in and out, and the out takes it to
  * nothing by 68% of the beat. When the next beat had no word the film
  * used to hand the picture `skyOn` to fade from — a number still sitting
  * near 1 — so a word that had been gone for seconds snapped back to 92%
  * on the frame after the cut and faded out a second time, across the
  * seam. Fade from what the word is wearing instead.
  */
  skyA = 0;
  /** the time of day the furniture is currently dressed for */
  wearing = "";
  /** the cast-shadow offset the type is currently wearing, px */
  shadow = {
    x: 0,
    y: 0
  };
  pageEl;
  static {
    decorateFieldV2(this.prototype, "fromRaw", [tracked4], function() {
      return (() => {
        const q = new URLSearchParams(window.location.search).get("from");
        const n = q ? Number(q) : 0;
        return Number.isFinite(n) && n > 0 ? n : 0;
      })();
    });
  }
  #fromRaw = (initializeDeferredDecorator(this, "fromRaw"), void 0);
  get from() {
    return Math.min(this.fromRaw, Math.max(0, this.all.length - 1));
  }
  set from(index) {
    this.fromRaw = index;
  }
  static {
    decorateFieldV2(this.prototype, "sound", [tracked4], function() {
      return false;
    });
  }
  #sound = (initializeDeferredDecorator(this, "sound"), void 0);
  static {
    decorateFieldV2(this.prototype, "gate", [tracked4], function() {
      return false;
    });
  }
  #gate = (initializeDeferredDecorator(this, "gate"), void 0);
  static {
    decorateFieldV2(this.prototype, "ready", [tracked4], function() {
      return false;
    });
  }
  #ready = (initializeDeferredDecorator(this, "ready"), void 0);
  static {
    decorateFieldV2(this.prototype, "rolling", [tracked4], function() {
      return false;
    });
  }
  #rolling = (initializeDeferredDecorator(this, "rolling"), void 0);
  /**
  * One pass BEHIND `booted`, on purpose. A region's first render
  * collects no score, so anything standing in it on that pass — the
  * first beat's type, a head photo — was never inserted and never
  * animates. Content mounts on this flag instead, which flips a tick
  * later: the same render that gives the score its first real pass
  * hands the front layer a genuine insertion, and the opening beat's
  * type is DELIVERED like every other beat's instead of being found
  * already on the glass.
  */
  get beats() {
    return this.from > 0 && !this.exact ? this.all.slice(this.from) : this.all;
  }
  /** the first beat of each chapter, in whole-film indices */
  get chapterHeads() {
    return chapterHeads(this.all);
  }
  /** where we are in the WHOLE film, not the current cut */
  get absoluteIndex() {
    return this.from + this.beatIndex;
  }
  get beat() {
    return this.beats[this.beatIndex] ?? this.beats[0] ?? EMPTY_BEAT;
  }
  static {
    decorateFieldV2(this.prototype, "subsOn", [tracked4], function() {
      return new URLSearchParams(window.location.search).has("subs");
    });
  }
  #subsOn = (initializeDeferredDecorator(this, "subsOn"), void 0);
  get subs() {
    return this.subsOn;
  }
  cc = () => {
    this.subsOn = !this.subsOn;
  };
  get grade() {
    return this.beat.grade ?? this.chapter.grade ?? "amber";
  }
  get chapter() {
    return this.chapters[this.beat.ch] ?? this.chapters[0] ?? EMPTY_CHAPTER;
  }
  get embed() {
    return (this.args.embed ?? false) || /[?&]embed\b/.test(window.location.search);
  }
  /** `?debug` puts the build stamp in the corner — see `@build` */
  get debug() {
    return /[?&]debug\b/.test(window.location.search);
  }
  get build() {
    return this.args.build ?? "";
  }
  get src() {
    const src = this.picture?.src;
    return src ? `${src}?host${AWAKE ? "&awake" : ""}` : "";
  }
  get photoSrc() {
    return `${this.assets}${this.beat.photo?.src ?? ""}`;
  }
  /** a photograph that failed to load is no photograph — drop the plate */
  lost = /* @__PURE__ */ new Set();
  static {
    decorateFieldV2(this.prototype, "lostStamp", [tracked4], function() {
      return 0;
    });
  }
  #lostStamp = (initializeDeferredDecorator(this, "lostStamp"), void 0);
  get hasPhoto() {
    const p = this.beat.photo;
    return !!p && this.lostStamp >= 0 && !this.lost.has(p.src);
  }
  missing = () => {
    const p = this.beat.photo;
    if (p) {
      this.lost.add(p.src);
      this.lostStamp += 1;
    }
  };
  /** a fresh name per lap (and per desk edit): an edited score replays */
  get filmName() {
    return `film-${this.lap}-${this.editStamp}`;
  }
  /**
  * The pose the score OPENS on, declared to the region — without it the
  * first spline segment travels in from the library's default rig, a
  * two-second bounce every cold boot wore before its first real frame.
  */
  get openPose() {
    const c = (this.beats[0] ?? EMPTY_BEAT).cam;
    return {
      dolly: c.dolly,
      look: {
        x: c.fx ?? 0,
        y: c.lookY,
        z: c.fz ?? 0
      },
      pitch: c.pitch,
      x: c.ox ?? 0,
      y: 0,
      yaw: c.yaw
    };
  }
  get filmSeconds() {
    return this.beats.reduce((n, b, i) => n + b.ticks + (i === 0 ? 0 : b.lead ?? 0), 0) * TICK;
  }
  /**
  * THE WHOLE FILM IS ONE CAMERA STEP.
  *
  * Every beat contributes its ticks as waypoints: a moving beat is sampled from
  * its head pose to its tail, a holding beat repeats its pose, and the
  * spline runs through the lot on one clock. So the shot list is a path
  * rather than a playlist, the camera crosses each mark with velocity
  * instead of arriving at it, and a hold is genuinely still without
  * anything having stopped.
  */
  /**
  * WHERE A SHOT ENDS — the beat's authored tail, floored so it always
  * reads as a move, and clamped so it never travels past the pose the
  * next shot begins on. Shared by the path (which lerps its waypoints
  * across it) and by the LAUNCH: a cut hands the chaser this shot's own
  * speed, so the lens is already travelling when the cut lands rather
  * than easing up from a standstill.
  */
  tailFor(bi) {
    return tailFor(this.beats, bi);
  }
  get path() {
    return waypoints(this.beats, this.from > 0);
  }
  /** the camera step's length: the film's, or the path's if it runs past */
  get pathSeconds() {
    return Math.max(this.filmSeconds, pathSecs(this.path));
  }
  /**
  * Each beat's entrance, as a delay into the one camera step — offset
  * one tick, because the pose-in-force seed occupies the spline's first
  * slot: waypoint k is crossed at (k+1) slots, not k. The old uniform
  * skew was invisible (camera and cues equally late, a constant the
  * chaser's own lag swallowed); a SPLICE made it audible — the snap
  * fired two seconds before the goal stepped, and the chaser spent the
  * gap dragged back toward the old shot. Cue 0 stays at zero: the boot
  * and every re-cut apply their head beat by hand, and its immediate
  * re-fire has always been the first cue's job.
  */
  get cues() {
    return cues(this.beats);
  }
  /**
  * THE ATTACHMENTS: every window the score drives another region over.
  * The plate for every beat, the insert for a beat with a photograph,
  * the clip for a beat with one — each on the score's own clock, so a
  * seek stands all of them where playing there would. The regions are
  * keyed per beat and mounted for their windows; `remove` past a window
  * leaves them to that; a clip may outlive its beat and holds.
  */
  get windows() {
    const beats = this.beats;
    const heads = cues(beats).filter((c) => c.action === "beat");
    const total = totalSecs(beats);
    const out = [];
    heads.forEach((c, k) => {
      const b = beats[k];
      const start2 = c.delay;
      const next2 = heads[k + 1]?.delay ?? total;
      out.push({
        end: "remove",
        length: next2 - start2,
        region: "plate",
        start: start2
      });
      if (b.photo) {
        out.push({
          end: "remove",
          length: next2 - start2,
          region: "insert",
          start: start2
        });
      }
      if (b.clip) {
        out.push({
          end: "hold",
          length: clipWindow(b.clip, start2, next2),
          region: "clip",
          start: start2 + (b.clip.at ?? 0)
        });
      }
    });
    return out;
  }
  /**
  * THE TRANSPORT — a broadcast bar, not a thermometer. One segment per
  * chapter, sized by the chapter's actual running time, filled by
  * WHOLE-film progress (the old bar measured the current cut, so a
  * skip made it lie), and clickable: the segments are the same re-cut
  * the menu and the arrows perform.
  */
  /**
  * ONE TIMELINE, NOT TWO.
  *
  * The corner carried a strip of chapter segments beside a rule of years:
  * two timelines of the same film, at two different scales, in two
  * different shapes, six inches apart. So the chapters are ON the years
  * now — each one a dot at the year it opens, so the gap between THE SITE
  * and SILENCE is fifty-four years wide and the gap between the last two
  * is a decade, which is the fact the film is about. The dots are still
  * the doors into the chapters.
  */
  get transport() {
    const here = this.absoluteIndex;
    const clock = this.args.clock;
    const total = this.totalSecs;
    return this.contents.map((c) => {
      const b = this.all[c.head];
      let at2;
      let label;
      if (clock) {
        const y = clock.yearAt(Array.isArray(b.build) ? b.build[0] : b.build ?? 0);
        const [a, z] = clock.span;
        at2 = Math.max(0, Math.min(1, (y - a) / (z - a)));
        label = String(Math.floor(y));
      } else {
        at2 = this.secsBefore(c.head) / total;
      }
      return {
        at: at2,
        done: here >= c.head,
        head: c.head,
        here: c.here,
        label,
        n: c.n,
        title: c.title
      };
    });
  }
  /** the ends of the rule, when it is a clock */
  get railLabels() {
    const span = this.args.clock?.span;
    return span ? [String(span[0]), String(span[1])] : void 0;
  }
  /** the rail is on unless the film says otherwise */
  get railOn() {
    return this.args.rail ?? true;
  }
  get railReadout() {
    return this.args.clock ? String(this.yearNow) : "";
  }
  /**
  * WHEN EACH CUE LANDS — paced against the voice, not the clock.
  *
  * The phrases used to arrive on four fixed delays, which meant a
  * fourteen-second beat finished its type with five seconds of dead air
  * and a short one crowded the read. So the cues spread themselves: the
  * first lands early, the last lands as the measured line is finishing
  * (`VO_SECS`), and a beat with no recording paces against two thirds of
  * its own length, which is where a read for it would sit anyway.
  */
  /**
  * THE TRANSITION FIRST, THEN THE TYPE. A setting that arrives while the
  * seam is still on screen is read against two pictures at once. The
  * block waits for the incoming join to finish and a breath more, then
  * enters in its order: kicker, glyph, reading — and the lines after.
  */
  get typeAt() {
    if (this.overOf(this.beat) === "everything") {
      return [0, 0.12, 0.36];
    }
    const wait = this.secsOf(this.beat.join ?? this.defaultJoin) + 0.45;
    return [wait, wait + 0.12, wait + 0.36];
  }
  get sayAt() {
    const b = this.beat;
    const n = b.says?.length ?? 0;
    const dur = b.ticks * TICK;
    const vo = this.voSecs[b.id];
    const first = this.typeAt[2] + 0.3;
    const last = Math.max(first + 0.8, Math.min(vo ? vo - 0.4 : dur * 0.66, dur - 1.4));
    return [0, 1, 2, 3].map((i) => n <= 1 ? first : first + Math.min(i, n - 1) * (last - first) / (n - 1));
  }
  /**
  * Thai and Khmer are not kanji: their ascenders, vowel marks and
  * subscripts stand far outside a CJK-tuned glyph box, so at the kanji
  * size they collide with the kicker above and the reading below. Tall
  * scripts take a reduced setting with real leading.
  */
  /**
  * HOW MANY CHARACTERS HAVE TO FIT. A vertical setting is as tall as
  * its string, and 一国一城令 is five glyphs — at the plate's own size
  * that column runs off the top of the frame and the film crops its
  * own title. The count goes to CSS, which sizes the column to the
  * height available rather than to a number somebody typed once while
  * looking at a three-glyph word.
  */
  get glyphFit() {
    return `--cf-glyphs:${Math.max(2, [...this.beat.kanji ?? ""].length)}`;
  }
  get glyphTone() {
    const k = this.beat.kanji ?? "";
    if (/[A-Za-zÀ-ÿ]/.test(k)) {
      return "is-latin";
    }
    return /[฀-๿ក-៿]/.test(k) ? "is-tall" : "";
  }
  /** the lineup's current kanji; empty between lineups */
  get stamp() {
    const c = this.beat.cycle;
    return c && this.cycleStep >= 0 ? c[this.cycleStep]?.kanji ?? "" : "";
  }
  /**
  * THE POSTER IS AN EVENING (by default). The film proper opens in the
  * morning, so the door stands in the last of the light with a long hard
  * shadow across the empty half of the frame; pressing it turns the day
  * over. The film may dress its door otherwise (`@poster`).
  */
  dressPoster(film) {
    const p = this.picture?.poster ?? {};
    film.theme(p.theme ?? 2, true);
    const l = p.light ?? {
      az: -105,
      el: 21
    };
    film.light({
      az: l.az * RAD,
      el: l.el * RAD
    });
  }
  announced = false;
  mount = modifier9((el) => {
    const rows = this.all.length;
    if (!this.announced) {
      this.announced = true;
      console.info(`film ${this.args.name}: ${this.args.build ?? ""}`);
    }
    this.frameEl = el;
    this.pageEl = el.closest(".cf-page");
    window.addEventListener("keydown", this.key);
    window.addEventListener("pointermove", this.aim);
    window.addEventListener("pointermove", this.wake);
    window.addEventListener("wheel", this.wake, {
      passive: true
    });
    document.addEventListener("fullscreenchange", this.fullChange);
    window.setTimeout(() => {
      if (this.booted) {
        this.wake();
      }
    }, 0);
    window.addEventListener("error", this.trip);
    window.addEventListener("unhandledrejection", this.trip);
    const port = this.regionPort;
    const frame2 = el.querySelector("iframe");
    if (!frame2 && !port) {
      return;
    }
    const pictureWindow = () => port ? {
      __film: port
    } : frame2.contentWindow;
    if (!this.args.contained) {
      document.body.classList.add(this.embed ? "cf-embedded" : "cf-film");
    }
    const reg = window.__choreo ??= {};
    reg[this.args.name] = {
      beats: () => this.all,
      chapters: () => this.chapters,
      clearPatch: this.clearPatch,
      exact: this.exact,
      patch: this.patch,
      renderAt: this.renderAt,
      /* the score's own clock, for laying a live capture against the
      pure camera: the pose at a frame is a function of THIS, not t */
      runTime: () => this.scoreCtx?.run?.time,
      runtime: () => this.runtime,
      schedule: () => this.filmSchedule,
      seconds: () => this.totalSecs,
      seek: this.seek,
      time: () => this.t,
      toggle: this.toggle
    };
    this.gate = this.from === 0 && !this.booted;
    const onLoad = () => {
      const w = pictureWindow();
      if (!w?.__film) {
        return;
      }
      if (!rows && !this.all.length) {
        return;
      }
      this.film = w.__film;
      this.takeGlass(this.film);
      this.film.volume?.(this.vol);
      this.film.schedule?.(this.pictureSchedule);
      if (this.booted) {
        return;
      }
      try {
        w.__film.time(this.standing);
        this.picture?.seat?.(w.__film);
        this.dressPoster(w.__film);
        this.snap((this.beats[0] ?? EMPTY_BEAT).cam);
      } finally {
        this.ready = true;
        this.args.onReady?.(this.handle);
      }
      if (this.gate) {
        if (this.wanted !== void 0) {
          this.begin(this.wanted);
          return;
        }
        this.posterAt = 0;
        this.posterRaf ??= requestAnimationFrame(this.poster);
        return;
      }
      if (!this.booted && this.from > 0) {
        this.begin(true);
      }
    };
    frame2?.addEventListener("load", onLoad);
    let bootTimer = 0;
    if (port || frame2.contentDocument?.readyState === "complete") {
      bootTimer = window.setTimeout(onLoad, 0);
    }
    if (this.booted) {
      const w = pictureWindow();
      if (w?.__film) {
        this.film = w.__film;
        this.takeGlass(this.film);
        this.film.volume?.(this.vol);
      }
      cancelAnimationFrame(this.raf);
      this.lastTick = performance.now();
      this.raf = requestAnimationFrame(this.frame);
    }
    return () => {
      cancelAnimationFrame(this.raf);
      window.clearTimeout(bootTimer);
      window.removeEventListener("keydown", this.key);
      window.removeEventListener("error", this.trip);
      window.removeEventListener("unhandledrejection", this.trip);
      window.removeEventListener("pointermove", this.aim);
      window.removeEventListener("pointermove", this.wake);
      window.removeEventListener("wheel", this.wake);
      document.removeEventListener("fullscreenchange", this.fullChange);
      window.clearTimeout(this.idleTimer);
      frame2?.removeEventListener("load", onLoad);
      document.body.classList.remove("cf-film", "cf-embedded");
      delete window.__choreo?.[this.args.name];
      this.film = void 0;
      this.takeGlass(void 0);
    };
  });
  trackEls = modifier9((el) => {
    this.lineEl = el.querySelector("line.cf-leader");
    this.tetherEl = el.querySelector("line.cf-tether");
    this.dotEl = el.querySelector("circle");
  });
  dimEl = modifier9((el) => {
    this.dim = el;
    return () => {
      if (this.dim === el) {
        this.dim = void 0;
      }
    };
  });
  /**
  * A JOIN OVERLAY LIVES EXACTLY AS LONG AS ITS ANIMATION.
  *
  * Every join paints the outgoing frame over the film and gets out of
  * the way — and "gets out of the way" was left to each overlay's own
  * last keyframe. The wipe's is a swept MASK, not an opacity, so when
  * it finished the element stayed at opacity 1 with a mask that did
  * not, in fact, hide it: a full-screen still of the previous shot sat
  * on top of the picture for the rest of the chapter. The camera went
  * on moving underneath, the captions went on changing, and the film
  * looked frozen one section behind itself — which is exactly what it
  * was. (It also explains a whole afternoon of "these shots barely
  * move": some of those frames were photographs.)
  *
  * So the overlay retires itself the moment its animation ends, and
  * the next cut builds a fresh one. No join can outlive its own play.
  */
  retire = modifier9((el) => {
    const done = () => {
      el.style.display = "none";
    };
    el.addEventListener("animationend", done);
    el.addEventListener("animationcancel", done);
    const failsafe = window.setTimeout(done, 1400);
    return () => {
      window.clearTimeout(failsafe);
      el.removeEventListener("animationend", done);
      el.removeEventListener("animationcancel", done);
    };
  });
  plate = modifier9((el) => {
    this.plateEl = el;
    this.rowEls = [...el.children];
    return () => {
      if (this.plateEl === el) {
        this.plateEl = void 0;
        this.rowEls = [];
      }
    };
  });
  snap(c, launch, secs) {
    this.goal = {
      ...c
    };
    this.mid = {
      ...c
    };
    this.now = {
      ...c
    };
    for (const k of ["dolly", "fx", "fz", "lookY", "ox", "pitch", "yaw"]) {
      const a = c[k] ?? 0;
      const b = launch ? launch[k] ?? 0 : a;
      this.midV[k] = secs ? (b - a) / secs * 0.45 : 0;
      this.nowV[k] = this.midV[k];
    }
    this.sent = void 0;
    this.film?.pose({
      az: c.yaw * RAD,
      el: c.pitch * RAD,
      fx: c.fx ?? 0,
      fz: c.fz ?? 0,
      lookY: c.lookY,
      ox: c.ox ?? 0,
      snap: true,
      zoom: c.dolly
    });
  }
  /**
  * THE WHIP. A 'whip' join does not snap: the goal steps across the
  * seam (the splice does that) and the chaser races it on a briefly
  * stiff spring — a fast, smooth tween between the shots that is over
  * in a third of a second and never reads as a glide. While it runs,
  * the spring is ~3× its documentary stiffness; then the hand relaxes.
  */
  whipUntil = 0;
  /**
  * One critically-damped stage. The page's own chase is the second, which
  * is the whole cascade argument getting made for free by the fact that the
  * scene lives in another document.
  */
  chase(dt) {
    const w = this.whipUntil > performance.now() ? 11 : 3.9;
    for (const k of ["dolly", "fx", "fz", "lookY", "ox", "pitch", "yaw"]) {
      const g = this.goal[k] ?? 0;
      const m = this.mid[k] ?? 0;
      const v = this.midV[k] + (w * w * (g - m) - 2 * w * this.midV[k]) * dt;
      this.midV[k] = v;
      const next2 = m + v * dt;
      this.mid[k] = next2;
      this.now[k] = next2;
    }
  }
  /**
  * THE POSTER TURNS.
  *
  * A still frame behind a title is indistinguishable from a JPEG, and
  * this whole film's argument is that it is not one. So while the door
  * is up the lens makes a slow circuit of the opening pose — a few
  * degrees either side, breathing in and out — which says "live 3D"
  * before a word is read and costs one rAF. It hands over on the
  * click: the film does not snap away from the poster, it flies from
  * wherever the circuit had reached.
  */
  poster = (stamp) => {
    if (!this.gate || this.booted) {
      this.posterRaf = void 0;
      return;
    }
    this.posterRaf = requestAnimationFrame(this.poster);
    const film = this.film;
    if (!film) {
      return;
    }
    if (!this.posterAt) {
      this.posterAt = stamp;
    }
    const t = (stamp - this.posterAt) / 1e3;
    const c = (this.beats[0] ?? EMPTY_BEAT).cam;
    const pose = this.lens2d ? {
      /* A 2D POSTER: the opening frame, a little closer, drifting —
       no orbit to swing, so it breathes in the zoom and the pan */
      dolly: c.dolly * (1.12 + 0.02 * Math.sin(t * 0.21 + 1.1)),
      lookY: c.lookY + 8e-3 * Math.sin(t * 0.17),
      ox: 0,
      pitch: c.pitch,
      yaw: c.yaw
    } : {
      dolly: c.dolly * (2.25 + 0.09 * Math.sin(t * 0.11 + 1.1)),
      lookY: c.lookY + 1.4 + 0.6 * Math.sin(t * 0.15),
      /* the two halves of the poster lean back toward the middle: the
      building comes in off the left edge, the wordmark off the right,
      and the gap between them is the composition */
      ox: (c.ox ?? 0) * 0.66,
      pitch: c.pitch + 2.4 + 1.4 * Math.sin(t * 0.13),
      yaw: c.yaw + 34 + 11 * Math.sin(t * 0.2)
    };
    film.pose({
      az: pose.yaw * RAD,
      el: pose.pitch * RAD,
      fx: c.fx ?? 0,
      fz: c.fz ?? 0,
      lookY: pose.lookY,
      ox: pose.ox,
      zoom: pose.dolly
    });
    this.posterPose = pose;
  };
  posterRaf;
  posterAt = 0;
  /** where the poster's circuit had reached when the door was answered */
  posterPose;
  /**
  * ONE SETTING AT A TIME, AND THIS TIME IT IS GUARANTEED.
  *
  * The hand-off is a leaver and an arriver sharing the corner for half
  * a second, which is the design. But a leaver whose exit never
  * completes just stays — and a block from the first beat was still
  * standing at full strength eight beats later, with two settings of
  * different chapters overprinting each other. Whatever strands it (a
  * removal that waits on a cue the outgoing beat never had), the rule
  * the film states out loud in its own comment is worth enforcing
  * rather than trusting: any block that is not the current one and has
  * outstayed the longest hand-off is taken off the glass.
  */
  sweepBlocks(now2) {
    const root = this.pageEl ?? this.frameEl ?? document.body;
    const blocks = root.querySelectorAll(".cf-type .cf-block");
    if (blocks.length < 2) {
      return;
    }
    for (let i = 0; i < blocks.length - 1; i++) {
      const el = blocks[i];
      const seen = Number(el.dataset["cfSeen"] ?? 0);
      if (blocks.length > 2 || seen && now2 - seen > 900) {
        el.remove();
      } else if (!seen) {
        el.dataset["cfSeen"] = String(now2);
      }
    }
  }
  frame = (stamp) => {
    this.raf = requestAnimationFrame(this.frame);
    this.tick(stamp);
  };
  tick(stamp) {
    this.sweepBlocks(stamp);
    const film = this.film;
    if (!film) {
      return;
    }
    if (document.hidden && !AWAKE) {
      return;
    }
    if (this.ended) {
      if (!this.idled) {
        film.idle(true);
        this.idled = true;
      }
      return;
    }
    if (this.idled) {
      film.idle(false);
      this.idled = false;
    }
    if (this.paused && !this.exact) {
      this.lastTick = stamp;
      return;
    }
    const dt = Math.min(0.08, this.lastTick ? (stamp - this.lastTick) / 1e3 : 0);
    this.lastTick = stamp;
    const jumpedNow = this.jumped;
    if (this.exact) {
      if (this.playing && this.rolling && !this.paused) {
        this.t = Math.min(this.totalSecs, this.t + dt);
      }
      this.fold();
      if (this.ended) {
        return;
      }
    }
    const since = this.exact ? this.t - this.beatStart(this.absoluteIndex) : (stamp - this.beatAt) / 1e3;
    this.driveSeam(film, this.t);
    if (this.exact) {
      this.now = {
        ...this.goal
      };
    } else {
      this.chase(dt);
    }
    const k = Math.min(1, dt * 1.8);
    this.lean.x += (this.leanTo.x - this.lean.x) * k;
    this.lean.y += (this.leanTo.y - this.lean.y) * k;
    const flown = flownOf(since, this.beat.ticks * TICK);
    const bob$1 = bob(flown, this.now.dolly, this.beat.bob ?? 0.5);
    const rise = this.followRise(film, dt);
    const lookY = rise ? rise.lookY : this.beat.hold === "top" ? (
      /* the cut line, kept a little above centre, never under the ground */
      Math.max(1.4, film.height() * 0.62) - this.rigMid
    ) : this.beat.hold && !this.beat.to ? film.height() * 0.5 - this.rigMid : this.now.lookY;
    const ox = Math.abs(this.now.ox ?? 0) < 1e-4 ? 0 : this.now.ox;
    const clock = this.exact ? this.t : stamp / 1e3;
    const hand$1 = hand(clock, this.now.dolly, HAND_AMP);
    const want = {
      /* the lens leans into the cursor: a couple of degrees of orbit and
      a hand's width of height, which is enough for the hills to move
      against the building and nowhere near enough to fight the shot */
      /* MOSTLY TILT. A machine in the air holds its heading far better
      than it holds its nose: yaw is what the operator is steering and
      pitch is what the wind is doing to it. So the wander is nearly
      all in the tilt, with a quarter of it in the orbit to keep the
      two from looking mechanically separate. */
      az: (this.now.yaw + this.lean.x * 0.8 + hand$1.az) * RAD,
      el: (this.now.pitch - this.lean.y * 0.5 + bob$1 + hand$1.el) * RAD,
      fx: this.now.fx ?? 0,
      fz: this.now.fz ?? 0,
      /* in a 2D lens a unit is the whole stage, not a storey */
      lookY: lookY + (this.lean.y * 0.3 + (this.beat.hold ? 0 : bob$1 * 0.3)) * (this.lens2d ? 0.012 : 1),
      ox: ox - this.lean.x * (this.lens2d ? 4e-3 : 0.012),
      zoom: Math.min(this.now.dolly, rise?.zoom ?? Infinity) * hand$1.zoom
    };
    const g = Math.min(1, dt * 12);
    const sent = this.exact ? {
      ...want
    } : this.sent ?? {
      ...want
    };
    if (!this.exact) {
      sent.az += (want.az - sent.az) * g;
      sent.el += (want.el - sent.el) * g;
      sent.fx += (want.fx - sent.fx) * g;
      sent.fz += (want.fz - sent.fz) * g;
      sent.lookY += (want.lookY - sent.lookY) * g;
      sent.ox += (want.ox - sent.ox) * g;
      sent.zoom += (want.zoom - sent.zoom) * g;
    }
    this.sent = sent;
    const eye = this.beat.eye;
    const lift = Math.max(0, Math.min(0.9, this.beat.lift ?? 0));
    const walk = eye?.to ? smooth(lift > 0 ? Math.min(1, flown / lift) : flown) : 0;
    if (lift > 0 && this.beat.toCam) {
      const from = this.beat.cam;
      const to2 = this.beat.toCam;
      const tilt = smooth(Math.max(0, Math.min(1, (flown - lift) / Math.max(0.1, 1 - lift))));
      sent.lookY = lerp(from.lookY ?? 0, to2.lookY ?? 0, tilt) + bob$1 * 0.3;
      sent.el = lerp(from.pitch, to2.pitch, tilt) * RAD + bob$1 * 0.5 * RAD;
    }
    film.pose({
      ...sent,
      /* and the page's own chase is stood down too: two integrators is
      two histories, and an exact film has none */
      snap: this.exact ? true : void 0,
      fov: eye ? eye.fov : null,
      near: eye ? [lerp(eye.at[0], (eye.to ?? eye.at)[0], walk), lerp(eye.at[1], (eye.to ?? eye.at)[1], walk), lerp(eye.at[2], (eye.to ?? eye.at)[2], walk)] : null
    });
    const mood = this.grade;
    const snap = this.gradeSnap;
    if (mood !== this.gradeSent || this.rakeDeg !== this.rakeSent) {
      const spec = this.grades[mood] ?? this.grades["amber"];
      film.grade({
        ...spec,
        rake: this.rakeDeg * RAD
      }, snap);
      this.gradeSnap = false;
      this.gradeSent = mood;
      this.rakeSent = this.rakeDeg;
    }
    const b = this.beat;
    const chapLut = this.chapters[b.ch ?? 0]?.lut ?? null;
    const lutName = b.lut === null ? null : b.lut ?? b.look ?? chapLut;
    if (lutName !== this.lutSent && film.lut) {
      const fx = this.lookFx[lutName ?? ""];
      film.lut(lutName === null ? null : lutName.includes(".") ? {
        amount: this.lutAmount,
        url: `${this.assets}luts/${lutName}`
      } : {
        ...fx ?? {
          amount: this.lutAmount
        },
        look: lutName
      }, snap);
      this.lutSent = lutName;
    }
    const goal = this.sunGoal;
    if (this.exact) {
      if (goal) {
        const from = this.sunFrom ?? goal;
        const k2 = smooth(Math.min(1, since / 1.5));
        this.sunNow = {
          az: from.az + wrapAngle(goal.az - from.az) * k2,
          el: lerp(from.el, goal.el, k2)
        };
        film.light(this.sunNow);
      }
    } else if (goal && this.sunNow) {
      const cap = 0.3 * dt;
      const ease3 = Math.min(1, dt * 1.6);
      const walk2 = (from, to2) => {
        const d2 = (to2 - from) * ease3;
        return from + (Math.abs(d2) > cap ? Math.sign(d2) * cap : d2);
      };
      let d = goal.az - this.sunNow.az;
      while (d > Math.PI) {
        d -= Math.PI * 2;
      }
      while (d < -Math.PI) {
        d += Math.PI * 2;
      }
      this.sunNow.az = walk2(this.sunNow.az, this.sunNow.az + d);
      this.sunNow.el = walk2(this.sunNow.el, goal.el);
      film.light(this.sunNow);
    }
    this.pageEl?.style.setProperty("--cf-lx", this.lean.x.toFixed(3));
    this.pageEl?.style.setProperty("--cf-ly", this.lean.y.toFixed(3));
    const at2 = this.exact ? this.t : this.secsBefore(this.absoluteIndex) + Math.min(this.beat.ticks * TICK, since);
    const total = this.totalSecs;
    const prog = this.scrubAt ?? Math.min(1, at2 / total);
    this.pageEl?.style.setProperty("--cf-prog", prog.toFixed(5));
    if (!this.args.clock) {
      this.pageEl?.style.setProperty("--cf-head", prog.toFixed(5));
    }
    if (this.trackW > 0) {
      this.pageEl?.style.setProperty("--cf-hpx", this.headPx(prog).toFixed(1));
    }
    const pct = Math.round(prog * 100);
    if (pct !== this.shownPct) {
      this.shownPct = pct;
      this.scrubEl?.setAttribute("aria-valuenow", String(pct));
    }
    const sec = Math.floor(at2);
    if (sec !== this.shownSec) {
      this.shownSec = sec;
      this.clock = _Film.mmss(at2);
    }
    this.clips(film, at2, jumpedNow);
    const beat = this.beat;
    const local = Math.min(1, since / (beat.ticks * TICK));
    if (Array.isArray(beat.build) && this.rolling) {
      const settle = beat.settle ?? 0;
      const span0 = beat.ticks * TICK;
      const bl = Math.max(0, Math.min(1, (since - settle) / Math.max(0.01, span0 - settle)));
      const t = lerp(beat.build[0], beat.build[1], smooth(Math.min(1, bl / (beat.buildBy ?? 1))));
      film.time(t);
      this.showYear(t);
    } else if (beat.build !== void 0) {
      this.showYear(Array.isArray(beat.build) ? beat.build[0] : beat.build);
    }
    const nextLead = this.all[this.absoluteIndex + 1]?.lead ?? 0;
    const span = (beat.ticks + nextLead) * TICK;
    const last = !this.all[this.absoluteIndex + 1];
    const endOff = !this.exact && this.beatIndex === 0 ? 0 : TICK;
    const typeA$1 = typeA({
      ended: this.ended,
      endOff,
      last,
      reveal: this.reveal,
      since,
      span,
      typeAt: this.typeAt[0]
    });
    this.pageEl?.style.setProperty("--cf-type-a", typeA$1.toFixed(3));
    const titleK$1 = titleK(beat.mode === "title", since, span);
    this.pageEl?.style.setProperty("--cf-title-k", titleK$1.toFixed(3));
    const stampA = this.stampAt(beat, local) * typeA$1;
    if (beat.stamp && (stampA > 2e-3 || this.stampOn)) {
      this.stampOn = stampA > 2e-3;
      const pal = film.palette();
      const night = luminance(pal.paper) < 0.42;
      film.sky("stamp", {
        color: night ? "rgba(247,240,224,0.5)" : "rgba(62,50,26,0.42)",
        family: this.worldFamily,
        lines: [String(beat.stamp.y)],
        shadow: night ? "rgba(0,0,0,0.35)" : "rgba(255,252,244,0.3)",
        shadowBlur: 0.12,
        size: 5.4,
        track: this.worldTrack * 0.5,
        weight: this.worldWeight
      }, {
        billboard: true,
        opacity: stampA * 0.9,
        x: -Math.sin(this.skyAz) * 34,
        y: 6.4,
        z: -Math.cos(this.skyAz) * 34
      });
    }
    if (this.plateEl) {
      this.plateEl.style.opacity = typeA$1.toFixed(3);
    }
    if (beat.hours?.length && this.rolling) {
      const over = beat.hoursOver ?? 1;
      const hl = Math.min(1, local / over);
      const step = Math.min(beat.hours.length - 1, Math.floor(hl * beat.hours.length));
      if (step !== this.hourStep) {
        this.hourStep = step;
        film.themeDur(beat.ticks * TICK * over / beat.hours.length);
        film.theme(beat.hours[step], false);
      }
    }
    const here = this.absoluteIndex;
    const tail = (this.all[here + 1]?.ch ?? -1) !== beat.ch;
    this.pageEl?.style.setProperty("--cf-ghost-a", ghostA(local, tail, this.stampAt(beat, local)).toFixed(3));
    if (beat.lightning !== void 0 && this.struck !== beat.id && since >= beat.lightning) {
      this.struck = beat.id;
      film.lightning();
    }
    if (beat.dissolve) {
      film.modelFade(1 - smooth(Math.max(0, (local - 0.12) / 0.72)));
    }
    const cloud$1 = cloud(local, this.beatIndex, beat.ticks * TICK);
    if (cloud$1 !== null) {
      film.haze((this.hazeBase ?? 0) + this.cloudHaze * cloud$1);
      this.setCloud(film, cloud$1);
    } else {
      this.setCloud(film, 0);
    }
    this.pushWash(film);
    if (beat.cycle?.length) {
      const step = Math.min(beat.cycle.length - 1, Math.floor(local * beat.cycle.length));
      if (step !== this.cycleStep) {
        this.cycleStep = step;
        const c = beat.cycle[step];
        if (c.style !== void 0 && film.style && film.styleIndex) {
          if (film.styleIndex() !== c.style) {
            film.style(c.style);
          }
        }
        film.time(c.year !== void 0 && this.args.clock ? this.args.clock.tAt(c.year) : this.standing);
        film.ping(step < beat.cycle.length - 1 ? 0 : 99);
      }
    }
    if (beat.sky) {
      const d = beat.sky.dist ?? 30;
      const a = this.skyAz;
      this.skyOn = this.exact ? skyIn(since) : this.skyOn + (1 - this.skyOn) * Math.min(1, dt * 1.6);
      film.sky("chapter", {
        /* HOLLOW, HUGE, AND NEARLY GONE. A filled glyph sharing air
        with the building is a stain on the lens; a hard outline is
        a diagram drawn on the sky. What the shot wants is a word
        the WEATHER is holding — twice the size, a hairline, and
        faint enough that the hill reads straight through it. */
        color: "rgba(252,247,236,0.34)",
        /* THE YEAR IS THE CENTENARY'S OWN NUMERAL. It was set in the
        page's old-style serif — the typography of the standalone
        study, not of this film — which read as a caption borrowed
        from somewhere else every time a date came up in the sky.
        Heavy grotesque, barely tracked, the way the programme sets
        a date. */
        family: this.worldFamily,
        lines: beat.sky.lines,
        shadow: "rgba(40,30,14,0.34)",
        shadowBlur: 0.16,
        size: beat.sky.size * 3.4,
        weight: this.worldWeight,
        /* LIGHT, not ink. Drawn in the same warm white the front door
        uses, at a hairline: over this film's grounds a pale
        outline reads as a word held in the air, where a dark one
        reads as a diagram printed on the sky. */
        track: beat.sky.track ?? this.worldTrack
      }, {
        billboard: true,
        opacity: this.skyA = skyOpacity(this.skyOn, local, beat.sky.opacity ?? 0.4),
        x: -Math.sin(a) * d,
        y: beat.sky.y,
        z: -Math.cos(a) * d
      });
    } else if (this.skyA > 1e-3 || this.skyOn > 1e-3) {
      this.skyOn = this.exact ? 0 : this.skyOn + (0 - this.skyOn) * Math.min(1, dt * 2.4);
      this.skyA = this.exact ? 0 : this.skyA + (0 - this.skyA) * Math.min(1, dt * 2.4);
      film.fade("chapter", this.skyA);
    }
    this.stageMark(film, beat, local, dt);
    this.trackPoint(film, beat, local, typeA$1);
    this.traceShape(film, beat, local, dt);
    this.parallax(local);
    this.follow(film);
    this.wear(film);
  }
  /**
  * TYPE THROWS ITS SHADOW WHERE THE BUILDING THROWS ITS OWN.
  *
  * The scene lights itself from a key whose position is a property of the
  * hour, and the tower's cast shadow lies along the ground at whatever
  * diagonal that produces. Type set over the frame with a shadow offset
  * down and right — the default of every drop shadow ever shipped — is
  * lit by a different sun than everything behind it, and the eye reads
  * the mismatch long before it can name it. So the key's own screen
  * position comes back from the scene and the offset is simply the
  * direction away from it. At night, or with the sun behind the lens,
  * there is no honest cast shadow and the type wears none.
  */
  follow(film) {
    const el = this.pageEl;
    if (!el) {
      return;
    }
    const s = film.sun();
    const cx = s.w / 2;
    const cy = s.h * 0.55;
    const dx = cx - s.x;
    const dy = cy - s.y;
    const len = Math.hypot(dx, dy) || 1;
    const throwPx = s.on ? 3.2 : 0;
    const nx = dx / len * throwPx;
    const ny = dy / len * throwPx;
    const q = (v) => Math.round(v * 10) / 10;
    if (q(nx) !== this.shadow.x || q(ny) !== this.shadow.y) {
      this.shadow = {
        x: q(nx),
        y: q(ny)
      };
      el.style.setProperty("--cf-shx", `${this.shadow.x}px`);
      el.style.setProperty("--cf-shy", `${this.shadow.y}px`);
      this.rakeDeg = q(Math.atan2(ny, nx) * 57.2958);
      el.style.setProperty("--cf-rake", `${this.rakeDeg}deg`);
    }
  }
  /** which of the frame's layers this picture draws itself */
  takeGlass(film) {
    this.washInGlass = !!film?.wash;
    this.cloudInGlass = !!film?.cloud;
    this.dimInGlass = !!film?.dim;
    this.washSent = "";
  }
  /**
  * THE WASH, TOLD ON A CHANGE. Two things decide it — the shot's own mode
  * and the palette's paper — and neither changes often, so the picture is
  * told when one does and eases the change itself over the same 700 ms
  * the stylesheet used to.
  */
  pushWash(film) {
    if (!film.wash) {
      return;
    }
    const mode = this.beat.bare ? "" : this.beat.mode ?? "";
    const sig = `${mode}|${this.paperNow}`;
    if (sig === this.washSent) {
      return;
    }
    this.washSent = sig;
    film.wash(mode, this.paperNow);
  }
  /** the cloud: into the glass where the picture takes it, onto a CSS plate where it does not */
  setCloud(film, k) {
    if (film.cloud) {
      film.cloud(k, this.rakeDeg);
      return;
    }
    this.pageEl?.style.setProperty("--cf-cloud", k.toFixed(3));
    this.pageEl?.classList.toggle("is-cloudless", k < 0.02);
  }
  /**
  * THE FURNITURE WEARS THE SCENE'S PALETTE.
  *
  * The page carries four times of day and swings its whole palette between
  * them, so a scrim and a caption painted in one fixed ochre are correct in
  * exactly one chapter and wrong in the other four — at noon the film's
  * warm paper sits on a cool scene like a sticker. The scene already
  * publishes its ink as CSS variables, so the film simply reads them and
  * dresses itself the same, once per change rather than once per frame.
  */
  wear(film) {
    const p = film.palette();
    if (!p.time) {
      return;
    }
    const GB = this.picture?.gradeLum ?? GRADE_LUM;
    const beat = this.beat;
    const dimmed = beat.trace || beat.to ? 0.74 : 1;
    const eff = luminance(p.paper) * (GB[this.grade] ?? 1) * dimmed * (1 - 0.25 * (beat.haze ?? 0));
    const dark = eff < 0.42;
    const ch = this.chapters[this.beat.ch ?? 0] ?? this.chapters[0];
    const sig = `${p.time}${dark ? "#d" : "#l"}${ch.n}`;
    if (sig === this.wearing) {
      return;
    }
    this.wearing = sig;
    const el = this.pageEl;
    if (!el) {
      return;
    }
    this.paperNow = p.paper;
    el.style.setProperty("--cf-paper", p.paper);
    el.style.setProperty("--cf-paper-a", rgba2(p.paper, 0.94));
    el.style.setProperty("--cf-paper-b", rgba2(p.paper, 0.76));
    el.style.setProperty("--cf-paper-c", rgba2(p.paper, 0));
    el.classList.toggle("is-dark", dark);
    el.style.setProperty("--cf-ink", dark ? "#f7f0e0" : p.ink);
    el.style.setProperty("--cf-ink2", dark ? "#bdb3a0" : p.ink2);
    el.style.setProperty("--cf-ink3", dark ? "#e6dcc8" : p.ink3);
    el.style.setProperty("--cf-accent", this.accentFor(dark, p.accent));
    el.style.setProperty("--cf-rule", p.rule);
    el.style.setProperty("--cf-chap", (dark ? ch.tintD : ch.tint) ?? this.accentFor(dark, p.accent));
  }
  /**
  * PLANES, MOVING AT THEIR OWN RATES.
  *
  * The world layer parallaxes because it is genuinely out in the scene at
  * different distances. The front layer has no depth to borrow, so it is
  * given one: over the life of a beat each row drifts and scales on its
  * own rate, the big glyph fastest and nearest, the small print slowest
  * and furthest, so the type reads as a set of planes rather than a
  * sheet. It is the oldest trick in motion graphics and it is here for
  * the oldest reason — a still caption over a moving picture looks
  * pasted on, and a caption that moves WITH the picture looks composited
  * into it.
  *
  * It runs on the beat's own clock rather than Motion's, deliberately:
  * the entrances belong to the score and this belongs to the shot, and
  * putting the two on one timeline would mean the drift restarting every
  * time a word did.
  */
  parallax(local) {
    const rows = this.rowEls;
    if (!rows.length) {
      return;
    }
    const t = smooth(Math.min(1, local * 1.6)) * (0.35 + 0.65 * local);
    const amp = this.beat.mode === "point" ? 0.35 : 1;
    const out = local > 0.93 ? Math.max(0, (1 - local) / 0.07) : 1;
    for (const [i, el] of rows.entries()) {
      const depth = 1 - i / Math.max(1, rows.length - 1);
      const rate = 1 + 0.22 * Math.sin(i * 2.4);
      const dx = -11 * t * amp;
      const dy = -(5 + 13 * depth) * t * amp * rate;
      const sc = 1 + 0.055 * depth * t * amp;
      el.style.transform = `translate3d(${dx.toFixed(2)}px,${dy.toFixed(2)}px,0) scale(${sc.toFixed(4)})`;
      el.style.opacity = out.toFixed(3);
    }
  }
  /**
  * THE TRACES LIVE IN THE SCENE NOW. They began as SVG projected over
  * the frame — approximately right and one frame behind the lens on
  * every move. As tubes in the page's own scene they are exact: they
  * lie ON the eave because they are geometry at the eave's own
  * coordinates, the building occludes them honestly, and the draw-on
  * is the tube's index buffer revealed in path order. Each line in a
  * set starts a moment after the one before it — a hand annotating,
  * not a diagram switching on.
  */
  /** how much of the follow is in force (eased), and its last aim and zoom */
  riseK = 0;
  riseAim = 0;
  riseZoom = 1;
  /**
  * THE LENS FOLLOWS THE WORK. Chris's rule for a building that goes up
  * in the shot: if a spire is rising, ZOOM OUT; as you push in, follow
  * the top that is being built. So while the followed campaign is
  * between its base and its top, the aim rides a little above the
  * middle of what stands and the zoom is capped to keep base and top
  * in the frame; when it finishes, the authored pose takes over again,
  * on a one-pole so the release is a move and not a jump.
  */
  followRise(film, dt) {
    const b = this.beat;
    const want = b.follow !== false && Array.isArray(b.build) ? film.rising?.(typeof b.follow === "string" ? b.follow : void 0) ?? null : null;
    const on5 = !!want && want.rising;
    if (this.exact) {
      if (!on5 || !want) {
        return null;
      }
      const span = Math.max(1.6, want.top - want.base + 1);
      const aim = want.base + 0.58 * (want.top - want.base) - this.rigMid;
      const zoom = Math.min(this.now.dolly, 7 / span);
      const k = smooth(Math.min(1, want.k / 0.12)) * (1 - smooth(Math.max(0, (want.k - 0.86) / 0.14)));
      return {
        lookY: lerp(this.now.lookY, aim, k),
        zoom: lerp(this.now.dolly, zoom, k)
      };
    }
    if (on5 && want) {
      const span = Math.max(1.6, want.top - want.base + 1);
      const aim = want.base + 0.58 * (want.top - want.base) - this.rigMid;
      const zoom = Math.min(this.now.dolly, 7 / span);
      const k = Math.min(1, dt / 1.1);
      this.riseAim += (aim - this.riseAim) * (this.riseK < 0.02 ? 1 : k);
      this.riseZoom += (zoom - this.riseZoom) * (this.riseK < 0.02 ? 1 : k);
    }
    this.riseK += ((on5 ? 1 : 0) - this.riseK) * Math.min(1, dt / 0.9);
    if (this.riseK < 0.01) {
      return null;
    }
    return {
      lookY: lerp(this.now.lookY, this.riseAim, this.riseK),
      zoom: lerp(this.now.dolly, this.riseZoom, this.riseK)
    };
  }
  /** the beat whose lines are being timed, and the local time they became drawable */
  traceBeat = "";
  traceFrom = -1;
  /** whether the beat's lines may be on the glass right now */
  traceOk = false;
  /**
  * NO LINE ON A THING STILL GOING UP. A trace or a callout is drawn on a
  * finished part: the followed campaign must be done (or, with nothing
  * followed, the built height must have passed the line). The draw-on
  * is timed from the moment that became true, not from the head.
  */
  traceReady(film, beat, local) {
    if (this.traceBeat !== beat.id) {
      this.traceBeat = beat.id;
      this.traceFrom = -1;
    }
    let ready = true;
    if (beat.follow !== false && Array.isArray(beat.build)) {
      const r = film.rising?.(typeof beat.follow === "string" ? beat.follow : void 0);
      if (typeof beat.follow === "string") {
        ready = !!r && r.done;
      } else {
        ready = !r || !r.rising;
      }
    }
    if (ready && this.traceFrom < 0) {
      this.traceFrom = local;
    }
    this.traceOk = ready && this.traceFrom >= 0;
    return this.traceOk;
  }
  traceShape(film, beat, local, dt) {
    const specs = beat.trace ?? [];
    let drew = 0;
    const gone = traceGone(local);
    const since = this.traceReady(film, beat, local) ? local - this.traceFrom : -1;
    for (const [i] of specs.entries()) {
      const draw = traceDraw(since, i);
      const undraw = traceUndraw(gone, i);
      drew = Math.max(drew, draw * (1 - undraw));
      if (undraw > 0 && film.traceUndraw) {
        film.traceUndraw(`t${i}`, undraw);
        film.traceFade(`t${i}`, undraw >= 1 ? 0 : 1);
      } else {
        film.traceDraw(`t${i}`, draw);
        film.traceFade(`t${i}`, 1 - undraw);
      }
    }
    if (beat.to) {
      drew = Math.max(drew, calloutDraw(since));
    }
    this.dimNow = this.exact ? drew : this.dimNow + (drew - this.dimNow) * Math.min(1, dt * 3.2);
    if (this.dimInGlass) {
      film.dim?.(this.dimNow);
    } else if (this.dim) {
      this.dim.style.opacity = this.dimNow.toFixed(3);
    }
  }
  /** the mark's facing, damped behind the camera's own bearing */
  markFace = 0;
  /**
  * Place the stage mark: climb to its height with a settle, hold, and
  * face the camera a beat late.
  */
  stageMark(film, beat, local, dt) {
    const m = beat.mark;
    const tether = this.tetherEl;
    if (!m) {
      film.fade("mark", 0);
      if (tether) {
        tether.style.opacity = "0";
      }
      return;
    }
    if (!this.markSeated && local >= (m.at ?? 0.14)) {
      this.markSeated = true;
      this.markFrom = Math.max(0.4, film.height() - 3.4);
    }
    const raw = Math.min(1, Math.max(0, (local - 0.04) / 0.2));
    const c1 = 0.45;
    const p = raw - 1;
    const rise = raw >= 1 ? 1 : 1 + (c1 + 1) * p * p * p + c1 * p * p;
    const y = m.to * rise;
    const a = m.bearing * RAD;
    const v = film.view();
    this.markFace = this.exact ? v.az : this.markFace + wrapAngle(v.az - this.markFace) * Math.min(1, dt * 1.6);
    film.sky("mark", {
      /* BIG, WHITE, SOFT, AND BEHIND. A dark label pasted over the
      scaffolding is a sticker; a big pale word standing further out
      than the structure — soft-edged, its own glow holding it
      against the hills, the building crossing in FRONT of it — is
      part of the place. */
      /* white OUTLINE, on its own plane behind the building, and
      smaller than the sky word: this one names a part rather than
      the chapter, so it stands at the height of the thing it names
      and keeps climbing with it. */
      /* BIGGER, FAINTER, AND IN THE SAME PLACE EVERY TIME. A word
      that lands somewhere new each beat is a caption chasing the
      building; one that always stands in the same spot behind it
      becomes a fixture of the film — you stop reading it as an
      annotation and start reading it as the name of what you are
      watching. Big enough to be architecture, faint enough that
      the timber crossing it always wins. */
      /* TINTED, not outlined. An outline is a drawing of a word; a
      tint is the word itself, standing in the same air as
      everything else and taking the same light. Grey because the
      sky it stands in is nearly white, and faint enough that the
      building crossing it always wins. */
      color: "rgba(78,71,56,0.3)",
      family: this.worldFamily,
      lines: m.lines,
      shadow: "rgba(255,252,244,0.28)",
      shadowBlur: 0.14,
      size: m.size * 2.7,
      track: this.worldTrack,
      weight: this.worldWeight
    }, {
      /* IN LATE, OUT EARLY. The word arrives after the shot has been
      running long enough to be about something, names the stage, and
      is gone before the middle — a title that outstays the moment it
      titles becomes furniture. */
      opacity: markOpacity(local, m.at ?? 0.14, m.hold ?? 0.34),
      ry: this.markFace / RAD % 360,
      /**
      * IT RISES OUT FROM BEHIND THE BUILDING. The word starts low
      * enough that the structure stands in front of it, fades up
      * while it is still half hidden, climbs past the frame the
      * carpenters are raising, and is gone before it reaches the top
      * of the picture — so the BUILDING reveals it, rather than a
      * caption appearing beside the building. Planted on one azimuth
      * so the camera moves PAST it, and nudged back toward the lens
      * if the orbit carries it out of frame (below).
      */
      x: Math.sin(this.markAz) * 26 + Math.cos(this.markAz) * this.markOff,
      /* a short climb, not a launch: the word should read as drifting
      up out of the structure over its whole life, not crossing the
      frame — same time on screen, a third of the distance */
      y: this.markFrom + Math.max(0, local - (m.at ?? 0.14)) * 7,
      z: Math.cos(this.markAz) * 26 - Math.sin(this.markAz) * this.markOff
    });
    const seen = film.project(Math.sin(this.markAz) * 26 + Math.cos(this.markAz) * this.markOff, this.markFrom + Math.max(0, local - (m.at ?? 0.14)) * 7, Math.cos(this.markAz) * 26 - Math.sin(this.markAz) * this.markOff);
    const lit = local > (m.at ?? 0.14) - 0.02 && local < (m.at ?? 0.14) + (m.hold ?? 0.34) + 0.02;
    const outside = lit && (!seen.on || seen.x < v.w * 0.12 || seen.x > v.w * 0.88);
    if (outside) {
      let d = v.az + Math.PI - this.markAz;
      while (d > Math.PI) {
        d -= Math.PI * 2;
      }
      while (d < -Math.PI) {
        d += Math.PI * 2;
      }
      this.markAz += d * Math.min(1, dt * 0.9);
    }
    if (tether && this.frameEl) {
      const host = this.frameEl.getBoundingClientRect();
      const sx = host.width / v.w;
      const sy = host.height / v.h;
      const from = film.project(Math.sin(a) * m.r * 0.72, y, Math.cos(a) * m.r * 0.72);
      const to2 = film.project(0, y, 0);
      tether.setAttribute("x1", String(from.x * sx));
      tether.setAttribute("y1", String(from.y * sy));
      const tk = Math.min(1, Math.max(0, (raw - 0.4) / 0.22));
      const fx = Number(tether.getAttribute("x1") ?? 0);
      const fy = Number(tether.getAttribute("y1") ?? 0);
      tether.setAttribute("x2", String(fx + (to2.x * sx - fx) * tk));
      tether.setAttribute("y2", String(fy + (to2.y * sy - fy) * tk));
      tether.style.opacity = tk > 0.01 ? "0.55" : "0";
    }
  }
  /**
  * THE TRACKING LINE — the one piece of the front layer that has to know
  * where the camera is pointing this frame. The caption stays where the
  * layout put it and a line reaches from it to the actual point on the
  * building, redrawn every frame, so the label is attached to the thing
  * rather than merely near it.
  */
  trackPoint(film, beat, local, typeA2) {
    const line = this.lineEl;
    const dot = this.dotEl;
    if (!line || !dot) {
      return;
    }
    if (!beat.to || !this.frameEl || !this.plateEl) {
      line.style.opacity = "0";
      dot.style.opacity = "0";
      return;
    }
    if (beat.to[1] > film.height() + 0.15) {
      line.style.opacity = "0";
      dot.style.opacity = "0";
      return;
    }
    const p = film.project(...beat.to);
    const v = film.view();
    const host = this.frameEl.getBoundingClientRect();
    const box = this.plateEl.getBoundingClientRect();
    const sx = host.width / v.w;
    const sy = host.height / v.h;
    const x2 = p.x * sx;
    const y2 = p.y * sy;
    const cx = box.left - host.left + box.width / 2;
    const cy = box.top - host.top + box.height / 2;
    const x1 = x2 > cx ? box.right - host.left : box.left - host.left;
    const y1 = cy;
    const gate = p.on && this.traceOk;
    const inK = Math.min(1, Math.max(0, (local - 0.12) / 0.16));
    const outK = Math.min(1, Math.max(0, (local - 0.78) / 0.16));
    const draw = gate ? inK : 0;
    const lift = gate ? outK : 1;
    const hx = x1 + (x2 - x1) * draw;
    const hy = y1 + (y2 - y1) * draw;
    const tx = x1 + (hx - x1) * lift;
    const ty = y1 + (hy - y1) * lift;
    line.setAttribute("x1", String(tx));
    line.setAttribute("y1", String(ty));
    line.setAttribute("x2", String(hx));
    line.setAttribute("y2", String(hy));
    dot.setAttribute("cx", String(x2));
    dot.setAttribute("cy", String(y2));
    line.style.opacity = draw > 0.01 && lift < 0.99 ? (0.75 * typeA2).toFixed(3) : "0";
    const vis = Math.max(0, draw - lift);
    dot.style.strokeDasharray = `${vis.toFixed(3)} 1`;
    dot.style.strokeDashoffset = String(-lift.toFixed(3));
    dot.style.opacity = vis > 5e-3 ? typeA2.toFixed(3) : "0";
  }
  /**
  * THE READOUT AND THE MARKER. The numeral is tracked and written only
  * when the whole year changes, which is a handful of times a run; the
  * marker's position is a custom property written every frame, because a
  * dot that steps once a year along a rule is a dot that looks broken.
  */
  /**
  * WHEN THE NUMERAL IS ON. It rises as the voice reaches the year, holds
  * while the phrase finishes, and is gone well before the cut — a date
  * that outstays the sentence that said it becomes a watermark.
  */
  stampAt(beat, local) {
    const st = beat.stamp;
    if (!st) {
      return 0;
    }
    const secs = beat.ticks * TICK;
    const read = this.voSecs[beat.id] ?? secs * 0.66;
    return stampAt(local, secs, read, this.typeAt[0], st.at ?? 0.06);
  }
  /** the film's clock readout, from page seconds — nothing without a clock */
  showYear(t) {
    const clock = this.args.clock;
    if (!clock) {
      return;
    }
    const y = clock.yearAt(t);
    const n = Math.floor(y);
    if (n !== this.yearSent) {
      this.yearSent = n;
      this.yearNow = n;
    }
    const [a, z] = clock.span;
    const p = Math.max(0, Math.min(1, (y - a) / (z - a)));
    this.pageEl?.style.setProperty("--cf-head", p.toFixed(4));
  }
  /** everything a beat changes in the world, done once on entry */
  applyBeat(beat, instant = false, seam) {
    const film = this.film;
    if (!film) {
      return;
    }
    this.beatAt = performance.now();
    this.cycleStep = -1;
    film.shot?.(beat.id);
    for (let i = 0; i < 4; i++) {
      film.clearTrace(`t${i}`);
    }
    const mag = (beat.cam.dolly + (beat.toCam?.dolly ?? beat.cam.dolly)) / 2;
    beat.trace?.forEach((spec, i) => {
      const r = Math.max(0.03, Math.min(0.2, (spec.wide ? 0.13 : 0.085) / mag));
      film.trace(`t${i}`, {
        pts: spec.pts,
        r
      });
    });
    if (beat.cut || beat.join) {
      const join4 = beat.join ?? this.defaultJoin;
      if (this.exact) {
        this.seamExact(film, beat, join4, seam);
      } else if (join4 === "whip") {
        this.whipUntil = performance.now() + 360;
      } else {
        let held = "";
        const deep = this.overOf(beat);
        const glass = this.glassFor(join4);
        if (glass) {
          film.freeze?.(true);
          this.glassKind = join4;
          this.glassName = glass.name ?? "";
          this.glassLen = this.secsOf(join4);
          this.glassColor = beat.dipTo ?? "#0d0905";
          this.reveal = 0;
          this.freeze = "";
          this.joinKind = "";
          if (beat.cut) {
            this.snap(beat.cam, this.tailFor(this.beatIndex), beat.ticks * TICK);
          }
        } else if (deep !== "everything" && (join4 === "blend" || join4 === "melt" || join4 === "dip")) {
          const live = beat.theme === void 0 && beat.wx === void 0 && beat.style === void 0 && beat.winter === void 0 && beat.grade === void 0 && !beat.hours;
          if (!film.dissolve(join4, void 0, live)) {
            const shot = film.snapshot();
            held = shot.length > 64 ? shot : "";
          }
        } else if (join4 !== "cut") {
          const shot = film.snapshot();
          held = shot.length > 64 ? shot : "";
        }
        const index = this.beatIndex;
        if (this.glassKind === join4) ;
        else if (held) {
          film.freeze?.(true);
        }
        this.seam.hold(this.glassKind === join4 ? "" : held, () => {
          if (this.glassKind === join4) {
            return;
          }
          film.freeze?.(false);
          this.freeze = held;
          if (beat.cut || join4 === "wipe") {
            this.snap(beat.cam, this.tailFor(index), beat.ticks * TICK);
          }
          if (join4 === "dip") {
            this.dipColor = beat.dipTo ?? "#0d0905";
            this.play("dip", deep);
          } else if (join4 === "flash") {
            this.play("flash", deep);
          } else if (join4 === "sweep") {
            this.lightSweep(film, beat);
          } else if (join4 === "defocus") {
            if (held) {
              this.play("defocus", deep);
            }
            this.liveEl?.animate([{
              filter: "blur(9px)"
            }, {
              filter: "blur(0px)"
            }], {
              duration: 700,
              easing: "cubic-bezier(0.3, 0, 0.3, 1)"
            });
          } else if (held) {
            if (join4 === "iris") {
              const v = film.view();
              const p = beat.to ? film.project(...beat.to) : void 0;
              const cx = p ? Math.max(12, Math.min(88, p.x / v.w * 100)) : 50;
              const cy = p ? Math.max(12, Math.min(88, p.y / v.h * 100)) : 50;
              this.irisAt = `--ix:${cx.toFixed(1)}%;--iy:${cy.toFixed(1)}%`;
              this.play("iris", deep);
            } else if (this.presentations[join4]?.component) {
              this.play(join4, deep);
            }
          }
        });
      }
    }
    if (film.style && film.styleIndex) {
      const style2 = beat.style ?? 0;
      if (film.styleIndex() !== style2) {
        film.style(style2);
        film.time(Array.isArray(beat.build) ? beat.build[0] : beat.build ?? this.standing);
      }
    }
    if (!beat.dissolve) {
      film.modelFade(1);
    }
    if (typeof beat.build === "number") {
      film.time(beat.build);
    } else if (Array.isArray(beat.build)) {
      film.time(beat.build[0]);
    } else {
      film.time(this.standing);
    }
    if (beat.sky) {
      const swing = beat.toCam ? (beat.toCam.yaw - beat.cam.yaw) * RAD / 2 : 0;
      this.skyAz = (this.film?.view().az ?? 0) + swing + (beat.sky.az ?? 0) * RAD;
    }
    if (beat.mark) {
      this.markAz = (this.film?.view().az ?? 0) + Math.PI;
      const lone = (beat.mark.lines[0] ?? "").length <= 1;
      this.markOff = 0;
      if (lone && this.film) {
        const a = this.markAz;
        const at2 = (k) => this.film.project(Math.sin(a) * 26 + Math.cos(a) * k, 9, Math.cos(a) * 26 - Math.sin(a) * k).x;
        this.markOff = at2(3.6) > at2(-3.6) ? 3.6 : -3.6;
      }
      this.markSeated = false;
      this.markFrom = (beat.mark.to ?? 8) * 0.34 - 1.6;
    }
    this.applyAir(beat, instant);
    if (beat.vo || beat.hush) {
      this.hush();
      this.speak(beat);
    } else if (!this.sound || !this.film?.speaking()) {
      this.film?.duck(1);
    }
    this.args.onBeat?.(beat, film);
  }
  /**
  * THE AIR OF A SHOT: grade, sun, haze, weather. Split out of the beat
  * so a chapter's sky can begin turning while the lens is still flying
  * into it — the `air` cue fires at the head of a lead, the beat's own
  * cue when it lands, and applying it twice is harmless because every
  * one of these is a set, not a step.
  */
  applyAir(beat, instant = false) {
    const hard = instant || !!beat.cut || beat.join !== void 0 && this.holdsStill(beat.join);
    const film = this.film;
    if (!film) {
      return;
    }
    if (beat.theme !== void 0) {
      film.theme(beat.theme, hard);
    }
    const want = beat.sun ? {
      az: beat.sun.az * RAD,
      el: beat.sun.el * RAD
    } : null;
    this.sunFrom = instant ? null : this.sunGoal;
    this.sunGoal = want;
    if (hard || !this.sunNow || !want) {
      this.sunNow = want ? {
        ...want
      } : null;
      film.light(this.sunNow);
    }
    this.struck = "";
    this.hourStep = -1;
    this.gradeSnap = hard;
    if (!beat.hours) {
      film.themeDur(null);
    }
    this.hazeBase = beat.haze ?? null;
    film.haze(this.hazeBase);
    if (beat.wx !== void 0) {
      film.wx(beat.wx, hard || !!beat.wxCut);
    }
    if (beat.winter !== void 0) {
      film.winter(beat.winter);
    }
    film.mix(beat.mix ?? null);
    film.tag(Array.isArray(beat.build) && beat.build[1] > beat.build[0]);
    film.rain(beat.rain ?? null);
    film.rim(beat.rim ?? null, true);
    film.quality?.(beat.quality ?? null);
    film.grass?.(beat.grass ?? false);
    if (beat.theme !== void 0) {
      this.hourNow = beat.theme;
    }
    film.city?.(beat.city ?? "glass", this.hourNow === 3 ? 0.08 : this.cityGlass);
    this.args.onAir?.(beat, film, hard);
  }
  /**
  * THE HOUR A CUT INHERITS.
  *
  * Theme and weather are stated where they CHANGE, so a beat halfway
  * through the film usually says nothing about either — which is right
  * for a film played from the top and wrong for one dropped into. A
  * deep link (or a chapter skip) would open in whatever sky was last
  * set, which since the front door became an evening meant the
  * construction chapter got built at dusk. So a cut resolves its own
  * hour first: walk back to the last beat that named one, and take it.
  */
  settleAir(index) {
    const film = this.film;
    if (!film) {
      return;
    }
    for (let i = index; i >= 0; i -= 1) {
      const t = this.all[i]?.theme;
      if (t !== void 0) {
        film.theme(t, true);
        break;
      }
    }
    for (let i = index; i >= 0; i -= 1) {
      const w = this.all[i]?.wx;
      if (w !== void 0) {
        film.wx(w, true);
        break;
      }
    }
    let winter = null;
    for (let i = index; i >= 0; i -= 1) {
      if (this.all[i]?.winter !== void 0) {
        winter = this.all[i].winter;
        break;
      }
    }
    film.winter(winter ?? null);
  }
  shot = (state) => {
    this.goal = {
      dolly: state.dolly,
      fx: state.look?.x ?? 0,
      fz: state.look?.z ?? 0,
      lookY: state.look?.y ?? 0,
      ox: state.x,
      pitch: state.pitch,
      yaw: state.yaw
    };
  };
  dispatch = (command) => {
    if (command.action === "lap") {
      this.end();
      return;
    }
    if (command.action === "air") {
      const i = Number(command.target);
      if (Number.isFinite(i) && this.beats[i]) {
        this.applyAir(this.beats[i]);
      }
      return;
    }
    if (command.action === "beat") {
      const i = Number(command.target);
      if (i === 0 && this.primedLap === this.lap) {
        this.primedLap = -1;
        this.beatIndex = 0;
        return;
      }
      if (Number.isFinite(i) && this.beats[i]) {
        this.beatIndex = i;
        this.applyBeat(this.beats[i]);
      }
    }
  };
  /**
  * PAUSE MEANS EVERYTHING STOPS. The score's run holds where it is (the
  * lens included), the page's own clock holds (grass, weather, the
  * build, the day), the audio graph suspends, and the beat clock is
  * shifted forward by the length of the hold on resume so the hours,
  * the build and the type pick up exactly where they stood. Tearing the
  * Sequence down was the old pause, and it re-ran the chapter on play.
  * An exact film's runs are already standing — its clock is the only
  * thing that has to hold.
  */
  toggle = () => {
    if (!this.playing) {
      return;
    }
    this.paused = !this.paused;
    this.pop(this.paused ? "pause" : "play");
    if (!this.exact) {
      const run = this.scoreCtx?.run ?? null;
      if (this.paused) {
        this.pausedAt = performance.now();
        run?.pause();
      } else {
        this.beatAt += performance.now() - this.pausedAt;
        run?.play();
      }
    }
    this.film?.hold?.(this.paused);
    this.film?.pause(this.paused);
  };
  /** any re-cut or restart clears a hold: the new run starts rolling */
  unhold() {
    if (this.paused) {
      this.paused = false;
      this.film?.hold?.(false);
      this.film?.pause(false);
    }
  }
  /**
  * SKIP A CHAPTER — by re-cutting, never by seeking.
  *
  * `from` moves to a chapter head, which changes the beat list, which
  * changes the path, the cues and the sequence's name all at once. The
  * region sees a different score and plays it from its head. Seeking the
  * existing run would be the obvious alternative and it would be wrong:
  * the lens is an integrator whose pose depends on where it has been, so
  * a run dropped into the middle of itself arrives with the wrong
  * velocity — the same reason `notes/sylva-one-world.md` calls the chaser
  * seek-unsafe and means it.
  */
  goChapter = (delta) => {
    const heads = this.chapterHeads;
    const here = this.absoluteIndex;
    let i = heads.findIndex((h, n) => here >= h && (heads[n + 1] ?? Infinity) > here);
    if (i < 0) {
      i = 0;
    }
    const restart = delta < 0 && here > heads[i];
    const next2 = restart ? i : Math.max(0, Math.min(heads.length - 1, i + delta));
    this.cutTo(heads[next2]);
  };
  cutTo(index, hard = false) {
    this.unhold();
    if (this.exact) {
      this.seek(this.beatStart(index));
      return;
    }
    this.from = index;
    this.beatIndex = 0;
    this.ended = false;
    this.playing = true;
    this.lap += 1;
    this.primedLap = this.lap;
    this.settleAir(index);
    this.applyBeat(this.all[index], true);
    this.snap(this.all[index].cam, hard ? void 0 : this.tailFor(0), hard ? void 0 : this.all[index].ticks * TICK);
  }
  /** an uncaught error anywhere becomes a visible line — a film that
  *  dies silently mid-reel cannot be debugged from a chair */
  trip = (e) => {
    if (this.fault) {
      return;
    }
    const err = e;
    this.fault = String(err.message ?? err.reason ?? "unknown fault").slice(0, 200);
  };
  prev = () => this.goChapter(-1);
  next = () => this.goChapter(1);
  key = (e) => {
    if (e.metaKey || e.ctrlKey || e.altKey) {
      return;
    }
    if (this.args.contained && !this.pageEl?.matches(":hover") && !this.pageEl?.contains(document.activeElement)) {
      return;
    }
    if (this.gate) {
      if (e.key === " " || e.key === "Enter") {
        e.preventDefault();
        this.begin(true);
      }
      return;
    }
    if (this.ended && (e.key === " " || e.key === "Enter")) {
      e.preventDefault();
      this.replay();
      return;
    }
    if (e.key === "ArrowRight") {
      e.preventDefault();
      this.next();
    } else if (e.key === "ArrowLeft") {
      e.preventDefault();
      this.prev();
    } else if (e.key === " " || e.key === "k" || e.key === "K") {
      e.preventDefault();
      this.toggle();
    } else if (e.key === "f" || e.key === "F") {
      this.screen();
    } else if (e.key >= "1" && e.key <= "9") {
      const head = this.chapterHeads[Number(e.key) - 1];
      if (head !== void 0) {
        this.pick(head);
      }
    } else if (e.key === "0" || e.key === "Home") {
      this.restart();
    } else if (e.key === "m" || e.key === "M") {
      this.hear();
    } else if (e.key === "c" || e.key === "C" || e.key === "Escape") {
      this.toc();
    } else if (e.key === "v" || e.key === "V") {
      this.cc();
    }
  };
  /**
  * THE NARRATION, one file per beat.
  *
  * `assets/vo/<id>.mp3`, played on the beat's entrance and stopped
  * when the beat changes. Per beat rather than one long track because
  * chapter skip RE-CUTS the film: a single track would have to be sought,
  * and a sought track against a re-cut score drifts inside a chapter.
  *
  * A missing file is silence, not an error. The film ships before the
  * voice does, and the score has to be right either way. While a line
  * plays the scene's own music ducks under it, which is the one piece of
  * mixing that cannot wait for a mix.
  */
  voSrc(beat) {
    return `${this.assets}vo/${beat.id}.mp3`;
  }
  /** ask the page to fetch and decode the line after this one, now */
  primeNext(beat) {
    const next2 = this.all[this.all.indexOf(beat) + 1];
    if (next2?.vo) {
      this.film?.voicePrime(this.voSrc(next2));
    }
  }
  /**
  * A BOUNDARY NEVER CLIPS THE VOICE — and every line has its own
  * throat. One shared element made politeness impossible: however
  * gently the old line was being faded, the new line's src swap
  * guillotined it mid-word. So an interrupted line keeps its OWN
  * element and fades there (~120ms, fast enough to read as a stop,
  * slow enough that no waveform is cut mid-cycle) while the new line
  * starts clean on a fresh one — the game-dialogue barge-in, which is
  * what a chapter skip actually is. ("Stop at the next word" is the
  * refinement this is built to take: an analyser watching for the
  * inter-word trough before the fade — see docs/choreo-splices.md.)
  */
  /**
  * A JOIN, EXHIBITED. Any seam as a pure overlay on whatever is playing —
  * no beat change, no snap: the transition itself, on the living
  * picture. What a cutting room's wall plate triggers.
  */
  preview = (join4) => {
    const film = this.film;
    if (!film || !this.booted) {
      return;
    }
    if ((join4 === "blend" || join4 === "melt") && film.dissolve(join4)) {
      this.freeze = "";
      return;
    }
    if (join4 !== "flash" && join4 !== "sweep" && join4 !== "whip") {
      const shot = film.snapshot();
      this.freeze = shot.length > 64 ? shot : "";
      if (!this.freeze && join4 !== "dip") {
        return;
      }
    }
    switch (join4) {
      case "defocus":
        this.play("defocus");
        this.liveEl?.animate([{
          filter: "blur(9px)"
        }, {
          filter: "blur(0px)"
        }], {
          duration: 700,
          easing: "cubic-bezier(0.3, 0, 0.3, 1)"
        });
        break;
      case "dip":
        this.dipColor = "#0d0905";
        this.play("dip");
        break;
      case "iris": {
        const v = film.view();
        const b = this.beat;
        const pt = b.to ? film.project(...b.to) : void 0;
        const cx = pt ? Math.max(12, Math.min(88, pt.x / v.w * 100)) : 50;
        const cy = pt ? Math.max(12, Math.min(88, pt.y / v.h * 100)) : 46;
        this.irisAt = `--ix:${cx.toFixed(1)}%;--iy:${cy.toFixed(1)}%`;
        this.play("iris");
        break;
      }
      case "sweep":
        this.lightSweep(film, this.beat);
        break;
      case "whip":
        this.whipUntil = performance.now() + 360;
        break;
      case "cut":
        break;
      default:
        this.play(join4);
    }
  };
  /** the wrapper the live picture sits in, for rack-defocus */
  liveEl;
  liveWrap = modifier9((el) => {
    this.liveEl = el;
    return () => {
      if (this.liveEl === el) {
        this.liveEl = void 0;
      }
    };
  });
  /**
  * THE LIGHT SWEEP: the sun itself flares across the seam — swings
  * high and past, then settles back onto whatever light the beat
  * actually asked for. Fire-and-forget; the restore hands the key
  * back to the beat's own sun (or the hour's).
  */
  lightSweep(film, beat) {
    const t0 = performance.now();
    const dur = 950;
    const base = beat.sun ? {
      az: beat.sun.az * RAD,
      el: beat.sun.el * RAD
    } : null;
    const step = () => {
      const f = (performance.now() - t0) / dur;
      if (f >= 1 || !this.film) {
        film.light(base);
        return;
      }
      const swing = Math.sin(f * Math.PI);
      film.light({
        az: (base?.az ?? 0.4) + (1 - f) * 2.2 - 1.1,
        el: (base?.el ?? 0.4) + swing * 0.3
      });
      requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  }
  /** the scene brought its own score — six of them, one per tower */
  /** the line for this beat, at the level the session was mixed to */
  speak(beat) {
    this.film?.voice(this.voSrc(beat), this.voGain[beat.id] ?? 1);
    this.primeNext(beat);
  }
  hush() {
    this.film?.voiceStop();
  }
  hear = () => {
    this.sound = !this.sound;
    this.film?.sound(this.sound);
    if (this.sound) {
      this.speak(this.beat);
    } else {
      this.hush();
    }
  };
  /**
  * FROM THE TOP means the front door, not the first beat.
  *
  * A film restarted straight into its opening shot skips the one piece
  * of the picture that says what it is — and the poster is a
  * composition in its own right, with the building turning in the last
  * of the light. So this clears everything the run has done and puts
  * the door back up, with the lens seated where it opens.
  */
  restart = () => {
    const film = this.film;
    this.unhold();
    this.freeze = "";
    this.film?.voiceStop(120);
    this.playing = false;
    this.ended = false;
    this.menu = false;
    this.from = 0;
    this.beatIndex = 0;
    this.markSeated = false;
    this.skyOn = 0;
    this.skyA = 0;
    this.dimNow = 0;
    this.sent = void 0;
    this.t = 0;
    this.jumped = false;
    this.seamAt = -1;
    this.endSeam();
    this.airedFor = -1;
    this.scoreRun = null;
    this.clipNow = null;
    this.clipKey = "";
    this.clipState = "absent";
    this.clipFreeze = "";
    if (film) {
      film.modelFade(1);
      film.rain(null);
      film.rim(null);
      film.fade("mark", 0);
      film.fade("chapter", 0);
      for (let i = 0; i < 4; i++) {
        film.clearTrace(`t${i}`);
      }
      film.duck(1);
      film.idle(false);
      this.idled = false;
      film.time(this.standing);
      this.picture?.seat?.(film);
      this.dressPoster(film);
      this.snap((this.all[0] ?? EMPTY_BEAT).cam);
    }
    this.booted = false;
    this.rolling = false;
    this.gate = true;
    this.posterAt = 0;
    this.posterRaf ??= requestAnimationFrame(this.poster);
  };
  /** a choice made at the door before the scene finished loading */
  wanted;
  /** through the gate — on the click the audio policy was waiting for */
  begin = (withSound) => {
    if (this.booted) {
      this.gate = false;
      if (withSound !== this.sound) {
        this.hear();
      }
      return;
    }
    if (!this.film) {
      this.wanted = withSound;
      return;
    }
    this.gate = false;
    if (this.posterRaf !== void 0) {
      cancelAnimationFrame(this.posterRaf);
      this.posterRaf = void 0;
    }
    this.sound = withSound;
    this.film.sound(withSound);
    if (this.exact) {
      const head = this.from;
      this.from = 0;
      this.t = this.beatStart(head);
      this.beatIndex = head;
      this.jumped = false;
      this.seamAt = -1;
      this.endSeam();
      this.airedFor = -1;
    }
    const first = this.exact ? this.all[this.beatIndex] : this.beats[0] ?? EMPTY_BEAT;
    this.settleAir(this.exact ? this.beatIndex : this.from);
    this.applyBeat(first, true);
    this.applyAir(first, false);
    if (this.posterPose && !this.exact) {
      this.now = {
        ...this.posterPose
      };
      this.mid = {
        ...this.posterPose
      };
      this.goal = {
        ...(this.beats[0] ?? EMPTY_BEAT).cam
      };
      this.whipUntil = performance.now() + 1200;
      for (const k of ["dolly", "fx", "fz", "lookY", "ox", "pitch", "yaw"]) {
        this.midV[k] = 0;
        this.nowV[k] = 0;
      }
    } else {
      this.snap(first.cam, this.tailFor(0), first.ticks * TICK);
    }
    this.playing = true;
    this.paused = false;
    this.booted = true;
    this.wake();
    this.lastTick = performance.now();
    this.raf = requestAnimationFrame(this.frame);
    window.setTimeout(() => {
      this.lap += 1;
      this.primedLap = this.lap;
      this.rolling = true;
    }, 0);
  };
  beginSound = () => this.begin(true);
  beginMute = () => this.begin(false);
  /** the whole film's running time, said the way a poster says it */
  get runtime() {
    const s = Math.round(this.all.reduce((n, b) => n + b.ticks, 0) * TICK);
    return `${Math.floor(s / 60)} min ${s % 60 ? `${s % 60} s` : ""}`.trim();
  }
  /**
  * BACK IN FROM THE END CARD — a dissolve, not a flight.
  *
  * The film ends three hundred degrees around the building from where
  * it opened, so tweening the lens home spins it like a globe. The
  * ending cross-fades into the opening frame instead: the last frame
  * is held as a still, the camera is PLACED at the opening pose behind
  * it, and the still fades away.
  */
  /**
  * BACK IN FROM THE END CARD — a hard reset, not a journey.
  *
  * The film ends three hundred degrees around the building, with the
  * tower dissolved, the sky at golden hour, the rain gone and a chapter
  * numeral on screen. Tweening any of that back to the opening is a
  * confusing ten seconds in which nothing is either the ending or the
  * beginning. So the ending is CLEARED: every overlay, the model, the
  * weather, the world type, the traces and the lens all go back to
  * their opening state in one frame, and the film starts.
  */
  /** the end card's WATCH AGAIN is the front door, not the first beat: the
  *  choice of sound is made there, every time */
  replay = () => {
    this.restart();
  };
  static {
    decorateFieldV2(this.prototype, "menu", [tracked4], function() {
      return false;
    });
  }
  #menu = (initializeDeferredDecorator(this, "menu"), void 0);
  toc = () => {
    this.menu = !this.menu;
  };
  /** every chapter, with the beat it starts at and whether we are in it */
  get contents() {
    const here = this.absoluteIndex;
    const heads = this.chapterHeads;
    return contents(this.all, this.chapters).map((c, i) => ({
      ...c,
      here: here >= c.head && here < (heads[i + 1] ?? this.all.length)
    }));
  }
  pick = (head) => {
    this.menu = false;
    this.cutTo(head);
  };
  static {
    setComponentTemplate15(precompileTemplate15(`
    <div class="cf-page is-{{@name}}
        {{if this.embed "is-embed"}}
        {{if @contained "is-contained"}}
        {{if this.idle "is-idle"}}">
      <div class="cf-stage is-grade-{{this.grade}} {{if this.subsOn "has-subs"}}" {{this.mount}} {{on "click" this.tap}} {{on "dblclick" this.tapTwice}}>
        {{!-- the live picture's own wrapper, so a rack-defocus can blur the
        scene without touching the grade riding the iframe itself --}}
        <div class="cf-live" {{this.liveWrap}}>
          {{#unless this.regionPort}}
            <iframe class="cf-frame" src={{this.src}} title={{this.frameTitle}} loading="eager"></iframe>
          {{/unless}}
          {{!-- THE PICTURE BLOCK STANDS IN THE STAGE. An iframe picture renders
          nothing here but its registration; a region picture renders the
          picture itself \u2014 ordinary DOM, in this document, under the lens --}}
          {{yield this.takePicture to="picture"}}
        </div>

        {{!-- A scrim, not a box: each setting gets a soft directional lift
        under it, which reads as light falling off and not as a panel. It is
        a layer here only for a picture that cannot take it into its own
        glass \u2014 where it can, the wash is inside the seam --}}
        {{#unless this.washInGlass}}
          <div class="cf-scrim cf-scrim-{{this.beat.mode}}
              {{if this.beat.bare "is-bare"}}" aria-hidden="true"></div>
        {{/unless}}

        {{!-- THE TRANSITIONS: the outgoing frame, held, and whatever the
        seam does to it --}}
        <div class="cf-joins {{if this.joinOver "is-over"}}" {{this.joinsWrap}}>
          <Joins @kind={{this.joinKind}} @stamp={{this.joinStamp}} @freeze={{this.freeze}} @irisAt={{this.irisAt}} @dipColor={{this.dipColor}} @seekable={{this.exact}} @presentations={{this.presentations}} />
        </div>
        {{!-- THE CLOUD, driven per frame from --cf-cloud \u2014 again only for a
        picture that cannot draw it in the glass --}}
        {{#unless this.cloudInGlass}}
          <div class="cf-cloud" aria-hidden="true"></div>
        {{/unless}}

        {{!-- THE DIM: a wash that comes in WITH an annotation and lifts with
        it \u2014 dimming the plate is what a lecturer does when the slide goes
        up --}}
        {{#unless this.dimInGlass}}
          <div class="cf-dim" aria-hidden="true" {{this.dimEl}}></div>
        {{/unless}}

        {{!-- the leader, the tether and the ring \u2014 what must connect DOM to
        world --}}
        <Track @wire={{this.trackEls}} />

        {{#if this.booted}}
          <Plate @beat={{this.beat}} @chapterN={{this.chapter.n}} @rolling={{this.rolling}} @typeAt={{this.typeAt}} @sayAt={{this.sayAt}} @glyphFit={{this.glyphFit}} @glyphTone={{this.glyphTone}} @mount={{this.plate}} />

          <Stamp @step={{this.cycleStep}} @word={{this.stamp}} />

          {{#if this.clipKey}}
            <Clip @key={{this.clipKey}} @spec={{this.clipSpec}} @src={{this.clipSrc}} @freeze={{this.clipFreeze}} @state={{this.clipState}} @mount={{this.clipEl}} />
          {{/if}}

          {{#if (if this.rolling this.hasPhoto false)}}
            <Insert @beat={{this.beat}} @src={{this.photoSrc}} @missing={{this.missing}} />
          {{/if}}

          {{#if this.subs}}
            <Captions @line={{this.beat.vo}} />
          {{/if}}

          {{#if this.fault}}
            <p class="cf-fault">\u26A0 {{this.fault}}</p>
          {{/if}}

          {{#if this.railOn}}
            <Rail @chapter={{this.chapter}} @marks={{this.transport}} @labels={{this.railLabels}} @readout={{this.railReadout}} @pick={{this.pick}} />
          {{/if}}
        {{/if}}

        {{!-- THE SCORE. One camera step for the whole film, and one clipped
        cue per beat \u2014 so the shot list and the script are the same object,
        and the film is a pure function of one clock. It waits for the
        scene: a rig on screen since the first pass was never inserted
        into anything, and the camera step would resolve to no subject. --}}
        {{#if this.booted}}
          <Choreo @onCamera3D={{this.shot}} @onPerform={{this.dispatch}} @camera3dFrom={{this.openPose}} as |c|>
            <i class="cf-rig" {{motion id="rig"}} {{this.grabScore c}} aria-hidden="true"></i>
            {{#if this.scoreOn}}
              <c.Sequence @name={{this.filmName}}>
                <c.Camera3D @name="film" @through={{this.path}} @duration={{this.pathSeconds}} @ease="linear" @tension={{0.34}} />
                {{!-- the type, the insert and the clip ride the score's clock:
                one window per beat, driven, never played --}}
                {{#each this.windows as |w|}}
                  <c.Attach @region={{w.region}} @at={{at "film"}} @delay={{w.start}} @duration={{w.length}} @end={{w.end}} @exact={{this.exact}} />
                {{/each}}
                {{!-- an exact film derives its beats from the clock; a cut
                film is told them --}}
                {{#unless this.exact}}
                  {{#each this.cues as |cue|}}
                    <c.Perform @at={{at "film"}} @delay={{cue.delay}} @action={{cue.action}} @target={{cue.index}} />
                  {{/each}}
                  <c.Perform @action="lap" />
                {{/unless}}
              </c.Sequence>
            {{/if}}
          </Choreo>
        {{/if}}

        {{#if this.gate}}
          <Gate @film={{this.handle}} as |f|>
            {{yield f to="gate"}}
          </Gate>
        {{/if}}

        {{#if this.ended}}
          <EndCard @film={{this.handle}} as |f|>
            {{yield f to="end"}}
          </EndCard>
        {{/if}}
      </div>

      {{#if this.menu}}
        <Menu @title={{@menuTitle}} @sub={{if @menuSub @menuSub "chapters"}} @contents={{this.contents}} @pick={{this.pick}} />
      {{/if}}

      {{!-- the confirmation glyph: a play or a pause, once, in the middle
      of the picture, gone in half a second --}}
      {{#if this.burst}}
        <Burst @kind={{this.burst}} @done={{this.burstDone}} />
      {{/if}}

      <Player @idle={{this.idle}} @away={{this.gate}} @live={{this.live}} @sound={{this.sound}} @loud={{this.loud}} @vol={{this.vol}} @volStyle={{this.volStyle}} @fade={{this.fade}} @full={{this.full}} @clock={{this.clock}} @duration={{this.duration}} @chapter={{this.chapter}} @subsOn={{this.subsOn}} @menu={{this.menu}} @debug={{this.debug}} @build={{this.build}} @playbar={{this.playbar}} @scrubAt={{this.scrubAt}} @tip={{this.tip}} @slider={{this.slider}} @trackWrap={{this.trackWrap}} @scrubDown={{this.scrubDown}} @scrubMove={{this.scrubMove}} @scrubUp={{this.scrubUp}} @scrubLeave={{this.scrubLeave}} @toggle={{this.toggle}} @prev={{this.prev}} @next={{this.next}} @hear={{this.hear}} @cc={{this.cc}} @toc={{this.toc}} @restart={{this.restart}} @screen={{this.screen}} />

      {{!-- under the stage: the film's SCORE, when it is written as a graph \u2014
      the markers compile to the table the engine runs --}}
      <FilmGraph @onCompile={{this.takeGraph}}>
        {{yield this.handle}}
      </FilmGraph>
    </div>

    <FilmStyles />
  `, {
      strictMode: true,
      scope: () => ({
        on: on4,
        Joins,
        Track,
        Plate,
        Stamp: Stamp2,
        Clip,
        Insert: Insert2,
        Captions,
        Rail,
        Choreo,
        motion: MotionModifier,
        at,
        Gate: Gate2,
        EndCard,
        Menu,
        Burst,
        Player,
        FilmGraph,
        FilmStyles
      })
    }), this);
  }
};

// dist/film/picture.js
import Component16 from "@glimmer/component";
import { modifier as modifier10 } from "ember-modifier";
import { precompileTemplate as precompileTemplate16 } from "@ember/template-compilation";
import { setComponentTemplate as setComponentTemplate16 } from "@ember/component";
var IframePicture = class extends Component16 {
  pending = 0;
  get spec() {
    const a = this.args;
    return {
      accent: a.accent,
      adjustments: IFRAME_PICTURE,
      assets: a.assets,
      cityGlass: a.cityGlass,
      cloudHaze: a.cloudHaze,
      gradeLum: a.gradeLum,
      grades: a.grades,
      lookFx: a.lookFx,
      lutAmount: a.lutAmount,
      poster: a.poster,
      rigMid: a.rigMid,
      seams: a.seams,
      seat: a.seat,
      src: a.src,
      srcdoc: a.srcdoc,
      standing: a.standing,
      title: a.title,
      worldType: a.worldType
    };
  }
  /** registers a frame after render, and again whenever an argument changes */
  attach = modifier10(() => {
    const spec = this.spec;
    if (this.pending) {
      cancelAnimationFrame(this.pending);
    }
    this.pending = requestAnimationFrame(() => {
      this.pending = 0;
      this.args.register(spec);
    });
    return () => {
      if (this.pending) {
        cancelAnimationFrame(this.pending);
        this.pending = 0;
      }
      this.args.register(null);
    };
  });
  static {
    setComponentTemplate16(precompileTemplate16("\n    <span hidden data-film-picture {{this.attach}}></span>\n  ", {
      strictMode: true
    }), this);
  }
};

// dist/film/lyric.js
import { array as array7, concat as concat3 } from "@ember/helper";
import Component17 from "@glimmer/component";
import { precompileTemplate as precompileTemplate17 } from "@ember/template-compilation";
import { setComponentTemplate as setComponentTemplate17 } from "@ember/component";
var SMALL = /* @__PURE__ */ new Set(["A", "AN", "THE", "TO", "OF", "FOR", "AND", "SO", "IS", "IT", "IN", "ON", "MY", "ME", "I", "I'M", "I'LL", "YOU", "YOU'RE", "YOUR", "BE", "AS", "BY", "WITH", "THAT", "OH", "CAN", "WE"]);
var clean = (w) => w.replace(/[^A-Z'ㄱ-힝]/g, "");
var Lyric = class extends Component17 {
  get size() {
    return this.args.size ?? 96;
  }
  get beat() {
    return this.args.beat ?? 60 / 90;
  }
  /** a song second on the eighth-note grid, at or before `t` */
  onGrid(t) {
    const step = this.beat / 2;
    const d = this.args.downbeat ?? 0;
    return d + Math.floor((t - d) / step) * step;
  }
  /** the phrase lands an eighth before it is sung, on the grid */
  get arrive() {
    const first = this.args.words[0]?.start ?? this.args.at;
    return Math.max(0, this.onGrid(first - 0.08) - this.args.at);
  }
  get leave() {
    return Math.max(this.arrive + 0.2, this.onGrid(this.args.exit) - this.args.at);
  }
  /** how long the phrase stays up, for its drift */
  get hold() {
    return Math.max(0.3, this.leave - this.arrive);
  }
  /** the drift's direction alternates line by line */
  get travel() {
    const n = [...this.args.id].reduce((a, ch) => a + ch.charCodeAt(0), 0);
    return (n % 2 ? 1 : -1) * this.size * 0.12;
  }
  get words() {
    const keys2 = new Set((this.args.keys ?? []).map((k) => clean(k.toUpperCase())));
    return this.args.words.map((w, i) => {
      const bare = clean(w.text);
      const weight = keys2.has(bare) ? "key" : SMALL.has(bare) ? "small" : "mid";
      return {
        hot: `${this.args.id}-h${i}`,
        sing: Math.max(0, w.start - this.args.at),
        span: Math.max(0.12, w.end - w.start),
        text: w.text,
        weight
      };
    });
  }
  get style() {
    return `--lyric-size:${this.size};font-family:${this.args.font ?? "Bagel Fat One"},sans-serif`;
  }
  static {
    setComponentTemplate17(precompileTemplate17('\n    <div class="cf-lyric" style={{this.style}} {{motion id=(concat @id "-line")}} ...attributes>\n      <div class="cf-lyric-words" {{motion id=(concat @id "-drift")}}>\n        {{#each this.words as |w|}}\n          <span class="cf-lyric-word {{w.weight}}">\n            <span class="cf-lyric-base">{{w.text}}</span>\n            <span class="cf-lyric-hot" aria-hidden="true" {{motion id=w.hot}}>{{w.text}}</span>\n          </span>\n        {{/each}}\n      </div>\n      {{#if @translation}}\n        <p class="cf-lyric-translation">{{@translation}}</p>\n      {{/if}}\n    </div>\n\n    {{!-- ARRIVAL \u2014 the phrase, as one, out of a blur --}}\n    <@c.Tween @of={{@c.id (concat @id "-line")}} @delay={{this.arrive}} @duration={{0.55}} @opacity={{array 0 1}} @y={{array 36 0}} @scale={{array 0.94 1}} @filter={{array "blur(14px)" "blur(0px)"}} @ease="expoOut" />\n    {{!-- DRIFT \u2014 never parked --}}\n    <@c.Tween @of={{@c.id (concat @id "-drift")}} @delay={{this.arrive}} @duration={{this.hold}} @scale={{array 1 1.035}} @x={{array 0 this.travel}} @ease="linear" />\n    {{!-- SWEEP \u2014 the light travels with the voice --}}\n    {{#each this.words as |w|}}\n      <@c.Tween @of={{@c.id w.hot}} @delay={{w.sing}} @duration={{w.span}} @clipPath={{array "inset(-20% 100% -20% 0)" "inset(-20% 0% -20% 0)"}} @ease="linear" />\n    {{/each}}\n    {{!-- EXIT \u2014 on the grid, into a blur --}}\n    <@c.Tween @of={{@c.id (concat @id "-line")}} @delay={{this.leave}} @duration={{0.36}} @opacity={{array 1 0}} @y={{array 0 -28}} @filter={{array "blur(0px)" "blur(10px)"}} @ease="expoIn" />\n  ', {
      strictMode: true,
      scope: () => ({
        motion: MotionModifier,
        concat: concat3,
        array: array7
      })
    }), this);
  }
};

// dist/film/reel.js
import { hash } from "@ember/helper";

// shim:renderer
import { join as join2, schedule as schedule4 } from "@ember/runloop";
function renderSettled() {
  return new Promise((resolve3) => join2(() => schedule4("afterRender", null, resolve3)));
}

// dist/film/reel.js
import Component18 from "@glimmer/component";
import { tracked as tracked5 } from "@glimmer/tracking";
import { valueForTag, CURRENT_TAG } from "@glimmer/validator";
import { modifier as modifier11 } from "ember-modifier";

// dist/film/wav.js
function encodeWav(buf) {
  const channels = buf.numberOfChannels;
  const frames2 = buf.length;
  const rate = buf.sampleRate;
  const bytes = frames2 * channels * 2;
  const out = new ArrayBuffer(44 + bytes);
  const v = new DataView(out);
  const ascii = (at3, s) => {
    for (let i = 0; i < s.length; i++) {
      v.setUint8(at3 + i, s.charCodeAt(i));
    }
  };
  ascii(0, "RIFF");
  v.setUint32(4, 36 + bytes, true);
  ascii(8, "WAVE");
  ascii(12, "fmt ");
  v.setUint32(16, 16, true);
  v.setUint16(20, 1, true);
  v.setUint16(22, channels, true);
  v.setUint32(24, rate, true);
  v.setUint32(28, rate * channels * 2, true);
  v.setUint16(32, channels * 2, true);
  v.setUint16(34, 16, true);
  ascii(36, "data");
  v.setUint32(40, bytes, true);
  const data = Array.from({
    length: channels
  }, (_, c) => buf.getChannelData(c));
  let at2 = 44;
  for (let i = 0; i < frames2; i++) {
    for (let c = 0; c < channels; c++) {
      const s = Math.max(-1, Math.min(1, data[c][i]));
      v.setInt16(at2, Math.round(s * 32767), true);
      at2 += 2;
    }
  }
  return out;
}
function wavBase64(wav) {
  const bytes = new Uint8Array(wav instanceof ArrayBuffer ? wav : encodeWav(wav));
  let bin = "";
  for (let i = 0; i < bytes.length; i += 32768) {
    bin += String.fromCharCode(...bytes.subarray(i, i + 32768));
  }
  return btoa(bin);
}

// dist/film/reel.js
import { precompileTemplate as precompileTemplate18 } from "@ember/template-compilation";
import { setComponentTemplate as setComponentTemplate18 } from "@ember/component";
var EPS = 1e-4;
var FONT_TIMEOUT = 1e4;
var RUN_POLLS = 240;
var AWAKE2 = new URLSearchParams(window.location.search).has("awake");
var frames = (n) => new Promise((resolve3) => {
  const step = () => n-- <= 0 ? resolve3() : requestAnimationFrame(step);
  requestAnimationFrame(step);
});
var macrotask = () => new Promise((r) => setTimeout(r, 0));
var ReelScene = class extends Component18 {
  /**
  * The reel this scene stands in. Each reel yields its own subclass with
  * this filled in — a bound argument would do the same, but the curried
  * component's type does not survive the trip into a consumer's Glint.
  */
  get reel() {
    throw new Error("a Reel scene is only used as the r.Scene a Reel yields");
  }
  /**
  * The span is the scene's handle on its own region: it lives inside the
  * `<Choreo>`, so it is the one place `c` and the reel meet. It reads the
  * take, which is what buys the scored pass a region skips on first
  * render.
  */
  wire = modifier11((el, [c, id2, at2, until, layer]) => {
    const section = el.closest(".cf-reel-scene");
    if (!section) {
      return;
    }
    section.style.zIndex = String(layer ?? 0);
    return this.reel.addScene({
      at: at2,
      c,
      el: section,
      id: id2,
      until
    });
  });
  static {
    setComponentTemplate18(precompileTemplate18('\n    <section class="cf-reel-scene" data-reel-scene={{@id}} ...attributes>\n      <Choreo @id={{@id}} class="cf-reel-region" as |c|>\n        <span hidden data-take={{this.reel.take}} {{this.wire c @id @at @until @layer}}></span>\n        {{yield c}}\n      </Choreo>\n    </section>\n  ', {
      strictMode: true,
      scope: () => ({
        Choreo
      })
    }), this);
  }
};
function sceneOf(reel) {
  return class extends ReelScene {
    get reel() {
      return reel;
    }
  };
}
var ReelLayer = class extends Component18 {
  /* written, never bound, as a scene's is */
  stack = modifier11((el, [z]) => {
    el.style.zIndex = String(z ?? 0);
  });
  static {
    setComponentTemplate18(precompileTemplate18('\n    <div class="cf-reel-layer" data-reel-layer={{@name}} {{this.stack @z}} ...attributes>\n      {{yield}}\n    </div>\n  ', {
      strictMode: true
    }), this);
  }
};
var ReelChrome = class extends Component18 {
  get reel() {
    throw new Error("a Reel chrome is only used as the r.Chrome a Reel yields");
  }
  static {
    setComponentTemplate18(precompileTemplate18("\n    {{#in-element this.reel.chromeEl insertBefore=null}}\n      {{yield}}\n    {{/in-element}}\n  ", {
      strictMode: true
    }), this);
  }
};
function chromeOf(reel) {
  return class extends ReelChrome {
    get reel() {
      return reel;
    }
  };
}
var Reel = class extends Component18 {
  static {
    decorateFieldV2(this.prototype, "take", [tracked5], function() {
      return 0;
    });
  }
  #take = (initializeDeferredDecorator(this, "take"), void 0);
  /** the one tracked write: bumped once, by prepare, to buy the scored pass */
  Scene = sceneOf(this);
  Layer = ReelLayer;
  Chrome = chromeOf(this);
  /**
  * The chrome's host: made here rather than in the template, so r.Chrome
  * can put its content in it from wherever it is invoked — inside the
  * yield, which is inside the stage — and it still lands outside it.
  */
  chromeEl = Object.assign(document.createElement("div"), {
    className: "cf-reel-chrome"
  });
  scenes = /* @__PURE__ */ new Set();
  clocked = [];
  clockedN = 0;
  /* the revision the last settled render left; a stand that finds the
   global one moved waits for the render before it stands the runs */
  settledRev = valueForTag(CURRENT_TAG);
  /* bumped by every stand, so one that waited can tell it was overtaken */
  standN = 0;
  lastStood;
  playingNow = false;
  resize;
  shell;
  preparing;
  /* plain, not tracked: read inside a modifier, the take would re-run it */
  ready = false;
  baking;
  injected = [];
  overflowBefore = "";
  /* the preview's transport: plain fields, never tracked */
  t = 0;
  loop = 0;
  listen;
  voice;
  get duration() {
    return this.args.duration;
  }
  get fps() {
    return this.args.fps ?? 60;
  }
  /** a layer on the clock that is not a scene; returns its removal */
  addClocked = (layer) => {
    const entry = {
      layer,
      n: this.clockedN++
    };
    this.clocked.push(entry);
    this.clocked.sort((a, b) => (a.layer.order ?? 0) - (b.layer.order ?? 0) || a.n - b.n);
    if (this.ready) {
      void this.stand(this.t, false).catch(() => {
      });
    }
    return () => {
      this.clocked = this.clocked.filter((e) => e !== entry);
    };
  };
  addScene(entry) {
    this.scenes.add(entry);
    if (this.ready) {
      void this.stand(this.t, false).catch(() => {
      });
    }
    return () => this.scenes.delete(entry);
  }
  /* ---- prepare, once ------------------------------------------------ */
  prepare() {
    return this.preparing ??= this.prepareOnce();
  }
  async prepareOnce() {
    const name = this.args.name;
    this.state("preparing");
    try {
      if (motionSpeed() !== 1) {
        throw new Error(`Reel "${name}": motionSpeed() is ${motionSpeed()}, and a reel is scored at 1\xD7`);
      }
      await Promise.all((this.args.stylesheets ?? []).map((h) => this.sheet(h)));
      for (const f of this.args.fonts ?? []) {
        await this.font(f);
      }
      await document.fonts.ready;
      await this.args.prepare?.();
      if (this.isDestroying) {
        return;
      }
      this.take++;
      await this.runs();
      this.ready = true;
      this.state("ready");
      const audio = this.args.audio;
      this.baking = audio ? Promise.resolve().then(() => audio()) : Promise.resolve(null);
      this.baking.catch(() => {
      });
    } catch (e) {
      this.state("failed");
      this.shell?.setAttribute("data-error", String(e.message ?? e));
      throw e;
    }
  }
  sheet(href) {
    const found = [...document.querySelectorAll('link[rel="stylesheet"]')].find((l) => l.href === new URL(href, location.href).href);
    if (found?.sheet) {
      return Promise.resolve();
    }
    const link = found ?? document.createElement("link");
    const loaded = new Promise((resolve3, reject) => {
      link.addEventListener("load", () => resolve3(), {
        once: true
      });
      link.addEventListener("error", () => reject(new Error(`Reel "${this.args.name}": ${href} failed to load`)), {
        once: true
      });
    });
    if (!found) {
      link.rel = "stylesheet";
      link.href = href;
      document.head.appendChild(link);
      this.injected.push(link);
    }
    return loaded;
  }
  /**
  * `fonts.load` resolves with the faces that matched — an empty list when
  * the face is not declared yet — so it is asked again until one answers.
  */
  async font(f) {
    const until = performance.now() + FONT_TIMEOUT;
    while (!(await document.fonts.load(f)).length) {
      if (performance.now() > until) {
        throw new Error(`Reel "${this.args.name}": no face answered "${f}"`);
      }
      await new Promise((r) => setTimeout(r, 50));
    }
  }
  /** wait for every scene's scored pass, pausing each run as it appears */
  async runs() {
    for (let i = 0; ; i++) {
      const missing = [];
      for (const s of this.scenes) {
        const run = s.c.run;
        if (!run) {
          missing.push(s.id);
        } else if (!run.paused) {
          run.pause();
        }
      }
      if (!missing.length) {
        return;
      }
      if (i >= RUN_POLLS) {
        throw new Error(`Reel "${this.args.name}": no run for ${missing.join(", ")} \u2014 a scene needs a step on a participant (a Wait alone is no run), and a score that compiles`);
      }
      await macrotask();
    }
  }
  /* ---- the clock ---------------------------------------------------- */
  /** is the scene on screen at t (already clamped)? */
  on(s, t) {
    const until = s.until ?? this.duration;
    return t + EPS >= s.at && (t + EPS < until || until >= this.duration);
  }
  /**
  * STAND EVERY SCENE AT t. The run is re-read on every call — a hot
  * reload or a stray render publishes a new one — and paused before it
  * is set. A scene off screen and already standing where it stands is
  * left alone: its pixels are hidden, and re-evaluating nine hidden
  * scenes a frame is most of a render's cost.
  */
  async stand(time2, settle = true, how = {}) {
    const t = Math.max(0, Math.min(this.duration, time2));
    this.t = t;
    const n = ++this.standN;
    await this.prepare();
    const layers = this.clocked.map((e) => e.layer);
    const info = {
      dt: 0,
      jumped: true,
      playing: !!how.playing,
      rendering: !!how.rendering
    };
    if (layers.length) {
      if (how.playing && this.lastStood !== void 0) {
        info.dt = Math.max(0, t - this.lastStood);
        info.jumped = false;
      }
      this.lastStood = t;
      for (const l of layers) {
        l.derive?.(t, info);
      }
      if (valueForTag(CURRENT_TAG) !== this.settledRev) {
        await renderSettled();
        this.settledRev = valueForTag(CURRENT_TAG);
        if (n !== this.standN || this.isDestroying) {
          return;
        }
      }
    }
    for (const s of this.scenes) {
      const on5 = this.on(s, t);
      const run = s.c.run;
      if (run) {
        const local = Math.max(0, Math.min(run.duration, t - s.at + EPS));
        if (on5 || run !== s.run || !run.paused || local !== s.local) {
          run.pause();
          run.time = local;
          s.run = run;
          s.local = local;
        }
      }
      s.el.style.visibility = on5 ? "visible" : "hidden";
    }
    for (const l of layers) {
      l.paint?.(t, info);
    }
    this.shell?.setAttribute("data-t", t.toFixed(4));
    if (settle) {
      await frames(2);
    }
  }
  /** the published renderAt: anything outside the reel takes the clock */
  renderAt = (t, opts) => {
    this.stop();
    if (this.chromeEl.childNodes.length) {
      this.shell?.setAttribute("data-rendering", "");
    }
    return this.stand(t, opts?.settle ?? true, {
      rendering: true
    });
  };
  audio = async () => {
    await this.prepare();
    const buffer = await this.baking;
    return buffer ? wavBase64(buffer) : null;
  };
  /* ---- the preview: paused, keyboard only ---------------------------- */
  state(s) {
    this.shell?.setAttribute("data-state", s);
  }
  /** the clock is taken back from the render: the chrome may show again */
  live() {
    this.shell?.removeAttribute("data-rendering");
  }
  /** stop the loop; says nothing to the sink (a seek restarts it) */
  halt() {
    this.playingNow = false;
    if (!this.loop) {
      return false;
    }
    cancelAnimationFrame(this.loop);
    this.loop = 0;
    try {
      this.voice?.stop();
    } catch {
    }
    this.voice = void 0;
    this.state("ready");
    return true;
  }
  stop() {
    if (this.halt()) {
      this.args.sink?.onPause?.();
    }
  }
  /* ---- the transport ------------------------------------------------ */
  get playing() {
    return this.playingNow;
  }
  time = () => this.t;
  play = async () => {
    this.live();
    if (this.playingNow) {
      return;
    }
    await this.run(true);
  };
  pause = () => {
    this.live();
    this.stop();
  };
  seek = async (time2) => {
    this.live();
    const was = this.playingNow;
    this.halt();
    const t = Math.max(0, Math.min(this.duration, time2));
    this.args.sink?.onSeek?.(t);
    await this.stand(t, false);
    if (was) {
      await this.run(false);
    }
  };
  /** the yielded transport: the reel's own methods, and a live `playing` */
  transport = (() => {
    const reel = this;
    return {
      pause: reel.pause,
      play: reel.play,
      get playing() {
        return reel.playing;
      },
      seek: reel.seek,
      time: reel.time
    };
  })();
  async run(announce) {
    this.playingNow = true;
    await this.prepare();
    const from = this.t >= this.duration ? 0 : this.t;
    const buffer = await this.baking?.catch(() => null);
    if (!this.playingNow || this.loop) {
      return;
    }
    let clock = () => performance.now() / 1e3;
    if (buffer) {
      this.listen ??= new AudioContext();
      const ctx = this.listen;
      await ctx.resume();
      const voice = ctx.createBufferSource();
      voice.buffer = buffer;
      voice.connect(ctx.destination);
      voice.start(0, from);
      this.voice = voice;
      clock = () => ctx.currentTime;
    }
    const zero = clock() - from;
    if (announce) {
      this.args.sink?.onPlay?.(from);
    }
    this.lastStood = from;
    const heard = this.args.sink?.clock;
    const tick = () => {
      const t = Math.max(0, heard?.() ?? clock() - zero);
      if (t >= this.duration) {
        void this.stand(this.duration, false, {
          playing: true
        });
        this.stop();
        this.args.onEnd?.();
        return;
      }
      if (!document.hidden || AWAKE2) {
        void this.stand(t, false, {
          playing: true
        });
      }
      this.loop = requestAnimationFrame(tick);
    };
    this.loop = requestAnimationFrame(tick);
    this.state("playing");
  }
  /** a key's step: the render's settle, but live — the chrome stays up */
  step(t) {
    this.live();
    this.stop();
    return this.stand(t);
  }
  onKey = (e) => {
    const target = e.target;
    if (e.metaKey || e.ctrlKey || e.altKey || target instanceof Element && target.closest("input, textarea, select, [contenteditable]")) {
      return;
    }
    const frame2 = 1 / this.fps;
    const step = e.shiftKey ? 10 * frame2 : frame2;
    const snap = (t) => Math.round(t * this.fps) / this.fps;
    switch (e.key) {
      case " ":
        if (this.playingNow) {
          this.pause();
        } else {
          void this.play();
        }
        break;
      case "ArrowLeft":
        void this.step(snap(this.t) - step);
        break;
      case "ArrowRight":
        void this.step(snap(this.t) + step);
        break;
      case "Home":
        void this.step(0);
        break;
      case "End":
        void this.step(this.duration);
        break;
      default:
        return;
    }
    e.preventDefault();
  };
  /* ---- mount -------------------------------------------------------- */
  mount = modifier11((shell) => {
    this.shell = shell;
    const stage = shell.querySelector(".cf-reel-stage");
    shell.style.background = this.args.background ?? "#0e0e0f";
    const contained = !!this.args.contained;
    if (contained) {
      shell.classList.add("is-contained");
    } else {
      this.overflowBefore = document.documentElement.style.overflow;
      document.documentElement.style.overflow = "hidden";
    }
    const w = this.args.width ?? 1920;
    const h = this.args.height ?? 1080;
    const fit = this.args.fit ?? "fixed";
    if (fit === "fill") {
      stage.style.width = "100%";
      stage.style.height = "100%";
    } else {
      stage.style.width = `${w}px`;
      stage.style.height = `${h}px`;
    }
    if (fit === "contain") {
      stage.style.transformOrigin = "0 0";
      const place = () => {
        const k = Math.min(shell.clientWidth / w, shell.clientHeight / h);
        const x = (shell.clientWidth - w * k) / 2;
        const y = (shell.clientHeight - h * k) / 2;
        stage.style.transform = `translate(${x}px, ${y}px) scale(${k})`;
      };
      place();
      this.resize = new ResizeObserver(place);
      this.resize.observe(shell);
    }
    const name = this.args.name;
    const handle = {
      audio: this.audio,
      exact: true,
      fps: this.fps,
      renderAt: this.renderAt,
      scenes: () => [...this.scenes].map((s) => ({
        at: s.at,
        duration: s.c.run?.duration ?? null,
        id: s.id,
        until: s.until ?? this.duration
      })),
      seconds: () => this.duration
    };
    const entry = this.args.publish ? {
      ...handle,
      ...this.args.publish(handle)
    } : handle;
    const reg = window.__choreo ??= {};
    reg[name] = entry;
    const keys2 = this.args.keys ?? true;
    if (keys2) {
      window.addEventListener("keydown", this.onKey);
    }
    const q = Number(new URLSearchParams(location.search).get("t"));
    this.stand(Number.isFinite(q) ? q : 0).catch((e) => console.error(e));
    return () => {
      this.stop();
      this.resize?.disconnect();
      this.resize = void 0;
      if (keys2) {
        window.removeEventListener("keydown", this.onKey);
      }
      const r = window.__choreo;
      if (r?.[name] === entry) {
        delete r[name];
      }
      if (!contained) {
        document.documentElement.style.overflow = this.overflowBefore;
      }
      for (const l of this.injected.splice(0)) {
        l.remove();
      }
      void this.listen?.close();
      this.listen = void 0;
    };
  });
  static {
    setComponentTemplate18(precompileTemplate18('\n    <div class="cf-reel" {{this.mount}} ...attributes>\n      <div class="cf-reel-stage">\n        {{yield (hash addClocked=this.addClocked Chrome=this.Chrome duration=this.duration fps=this.fps Layer=this.Layer Scene=this.Scene transport=this.transport)}}\n      </div>\n      {{this.chromeEl}}\n    </div>\n    <style>\n      .cf-reel {\n        position: fixed;\n        inset: 0;\n        z-index: 10000;\n        overflow: hidden;\n      }\n      .cf-reel-stage {\n        position: absolute;\n        left: 0;\n        top: 0;\n        overflow: hidden;\n      }\n      /* hidden until the clock first stands it: before prepare every\n         scene is at its CSS rest, and they are all on top of each other */\n      .cf-reel-scene {\n        position: absolute;\n        inset: 0;\n        visibility: hidden;\n      }\n      .cf-reel-region {\n        position: absolute;\n        inset: 0;\n      }\n      .cf-reel.is-contained {\n        position: relative;\n        inset: auto;\n        z-index: auto;\n        width: 100%;\n        height: 100%;\n      }\n      .cf-reel-layer {\n        position: absolute;\n        inset: 0;\n      }\n      /* over the stage, but only where it has something: an empty chrome\n         must not take the pointer from the picture */\n      .cf-reel-chrome {\n        position: absolute;\n        inset: 0;\n        pointer-events: none;\n      }\n      .cf-reel-chrome > * {\n        pointer-events: auto;\n      }\n      .cf-reel[data-rendering] .cf-reel-chrome {\n        visibility: hidden;\n      }\n    </style>\n  ', {
      strictMode: true,
      scope: () => ({
        hash
      })
    }), this);
  }
};

// dist/film/region.js
import { hash as hash2 } from "@ember/helper";
import Component19 from "@glimmer/component";
import { tracked as tracked6 } from "@glimmer/tracking";
import { modifier as modifier12 } from "ember-modifier";

// dist/film/soundtrack.js
var CHORDS = [
  [174.61, 220, 261.63, 329.63],
  // Fmaj7
  [130.81, 196, 246.94, 329.63],
  // Cmaj7
  [146.83, 174.61, 220, 329.63],
  // Dm9, near enough
  [116.54, 146.83, 174.61, 220]
  // Bbmaj7
];
function renderTrack(spec, rate = 44100) {
  const total = Math.max(1, spec.total);
  const ctx = new OfflineAudioContext(2, Math.ceil((total + 1) * rate), rate);
  const master = ctx.createDynamicsCompressor();
  master.threshold.value = -14;
  master.ratio.value = 3;
  master.connect(ctx.destination);
  const noise = ctx.createBuffer(1, rate * 2, rate);
  const nd = noise.getChannelData(0);
  let seed = 7;
  for (let i = 0; i < nd.length; i++) {
    seed = seed * 16807 % 2147483647;
    nd[i] = seed / 2147483647 * 2 - 1;
  }
  if (spec.bed) {
    const bed = ctx.createGain();
    const lp = ctx.createBiquadFilter();
    lp.type = "lowpass";
    lp.frequency.value = 1400;
    lp.Q.value = 0.4;
    bed.connect(lp).connect(master);
    const BAR = 8;
    for (let b = 0; b * BAR < total + 2; b++) {
      const ch = CHORDS[b % CHORDS.length];
      const t0 = b * BAR;
      ch.forEach((f, i) => {
        for (const det of [-4, 4]) {
          const o = ctx.createOscillator();
          o.type = i === 0 ? "triangle" : "sawtooth";
          o.frequency.value = f;
          o.detune.value = det;
          const g = ctx.createGain();
          const pk = i === 0 ? 0.03 : 0.012;
          g.gain.setValueAtTime(0, t0);
          g.gain.linearRampToValueAtTime(pk, t0 + 2.5);
          g.gain.setValueAtTime(pk, t0 + BAR - 0.5);
          g.gain.linearRampToValueAtTime(0, t0 + BAR + 2.5);
          o.connect(g).connect(bed);
          o.start(t0);
          o.stop(t0 + BAR + 2.6);
        }
      });
      const sub = ctx.createOscillator();
      sub.frequency.value = ch[0] / 2;
      const sg = ctx.createGain();
      sg.gain.setValueAtTime(0, t0);
      sg.gain.linearRampToValueAtTime(0.06, t0 + 1.5);
      sg.gain.linearRampToValueAtTime(0, t0 + BAR + 1);
      sub.connect(sg).connect(bed);
      sub.start(t0);
      sub.stop(t0 + BAR + 1.1);
      const step = 0.3125;
      const arp = [0, 2, 1, 3, 2, 1, 3, 2];
      for (let k = 0; k < BAR / step; k++) {
        const tt = t0 + k * step;
        if (tt < 3 || tt > total - 1.5 || k % 8 === 7) {
          continue;
        }
        const o = ctx.createOscillator();
        o.type = "triangle";
        o.frequency.value = ch[arp[k % 8]] * 2;
        const g = ctx.createGain();
        g.gain.setValueAtTime(0, tt);
        g.gain.linearRampToValueAtTime(k % 4 === 0 ? 0.03 : 0.018, tt + 8e-3);
        g.gain.exponentialRampToValueAtTime(5e-4, tt + 0.28);
        o.connect(g).connect(bed);
        o.start(tt);
        o.stop(tt + 0.3);
      }
    }
    const duck = bed.gain;
    duck.setValueAtTime(0, 0);
    duck.linearRampToValueAtTime(0.9, 1.5);
    for (const v of spec.voice) {
      duck.setTargetAtTime(0.42, Math.max(0, v.at - 0.1), 0.12);
      duck.setTargetAtTime(0.9, v.at + v.read, 0.35);
    }
    duck.setTargetAtTime(0, Math.max(0, total - 1.2), 0.5);
  }
  const out = ctx.createGain();
  out.gain.value = 0.9;
  out.connect(master);
  const burst2 = (t, dur, f0, f1, q, peak, type = "bandpass") => {
    const s = ctx.createBufferSource();
    s.buffer = noise;
    const f = ctx.createBiquadFilter();
    f.type = type;
    f.Q.value = q;
    f.frequency.setValueAtTime(f0, t);
    f.frequency.exponentialRampToValueAtTime(f1, t + dur);
    const g = ctx.createGain();
    g.gain.setValueAtTime(0, t);
    g.gain.linearRampToValueAtTime(peak, t + Math.min(0.02, dur / 4) + (dur > 0.2 ? dur * 0.35 : 0));
    g.gain.exponentialRampToValueAtTime(5e-4, t + dur);
    s.connect(f).connect(g).connect(out);
    s.start(t, t * 0.37 % 1.5);
    s.stop(t + dur + 0.05);
  };
  const tone = (t, f0, f1, dur, peak) => {
    const o = ctx.createOscillator();
    o.frequency.setValueAtTime(f0, t);
    o.frequency.exponentialRampToValueAtTime(f1, t + dur);
    const g = ctx.createGain();
    g.gain.setValueAtTime(0, t);
    g.gain.linearRampToValueAtTime(peak, t + 5e-3);
    g.gain.exponentialRampToValueAtTime(5e-4, t + dur);
    o.connect(g).connect(out);
    o.start(t);
    o.stop(t + dur + 0.02);
  };
  for (const {
    gain,
    kind,
    t
  } of spec.cues) {
    if (t < 0 || t > total) {
      continue;
    }
    switch (kind) {
      case "click":
        burst2(t, 0.03, 3200, 2400, 1.5, 0.35 * gain, "highpass");
        tone(t, 1900, 1500, 0.04, 0.08 * gain);
        break;
      case "tick":
        tone(t, 2600, 2400, 0.03, 0.05 * gain);
        break;
      case "pop":
        tone(t, 680, 300, 0.14, 0.16 * gain);
        break;
      case "thunk":
        tone(t, 160, 60, 0.2, 0.3 * gain);
        burst2(t, 0.06, 900, 500, 1, 0.12 * gain);
        break;
      case "whoosh":
        burst2(Math.max(0, t - 0.12), 0.55, 380, 2600, 1.1, 0.16 * gain);
        break;
      case "shutter":
        burst2(t, 0.035, 4e3, 3e3, 1, 0.3 * gain, "highpass");
        burst2(t + 0.07, 0.05, 3e3, 2e3, 1, 0.25 * gain, "highpass");
        break;
      case "chime":
        [880, 1318.5, 1760, 2637].forEach((f, i) => tone(t + i * 0.06, f, f, 1.8, 0.035 * gain));
        break;
      case "swell":
        burst2(Math.max(0, t - 0.6), 1.1, 200, 1800, 0.7, 0.1 * gain, "lowpass");
        break;
    }
  }
  return ctx.startRendering();
}
var TrackPlayer = class {
  ctx;
  gain;
  src;
  startedCtx = 0;
  startedAt = 0;
  level = 0.85;
  on = true;
  buffer = null;
  ensure() {
    if (!this.ctx) {
      this.ctx = new AudioContext();
      this.gain = this.ctx.createGain();
      this.gain.gain.value = this.on ? this.level : 0;
      this.gain.connect(this.ctx.destination);
    }
    if (this.ctx.state === "suspended") {
      void this.ctx.resume();
    }
    return this.ctx;
  }
  stop() {
    if (this.src) {
      try {
        this.src.stop();
      } catch {
      }
      this.src.disconnect();
      this.src = void 0;
    }
  }
  at(t, playing, jumped) {
    if (!this.buffer || !playing) {
      this.stop();
      return;
    }
    const ctx = this.ensure();
    const expected = this.src ? this.startedAt + (ctx.currentTime - this.startedCtx) : NaN;
    if (!this.src || jumped || !(Math.abs(expected - t) < 0.12)) {
      this.stop();
      if (t >= this.buffer.duration - 0.05) {
        return;
      }
      const src = ctx.createBufferSource();
      src.buffer = this.buffer;
      src.connect(this.gain);
      this.startedCtx = ctx.currentTime + 0.01;
      this.startedAt = t;
      src.start(this.startedCtx, Math.max(0, t));
      this.src = src;
    }
  }
  sound(on5) {
    this.on = on5;
    if (this.gain) {
      this.gain.gain.value = on5 ? this.level : 0;
    }
  }
  pause() {
    this.stop();
  }
  destroy() {
    this.stop();
    void this.ctx?.close();
  }
};

// dist/film/region.js
import { precompileTemplate as precompileTemplate19 } from "@ember/template-compilation";
import { setComponentTemplate as setComponentTemplate19 } from "@ember/component";
var REGIONS = /* @__PURE__ */ new WeakMap();
var Drive = class extends Component19 {
  static {
    decorateFieldV2(this.prototype, "take", [tracked6], function() {
      return 0;
    });
  }
  #take = (initializeDeferredDecorator(this, "take"), void 0);
  hold = modifier12((el, [c, from]) => {
    let release = () => {
    };
    const id2 = requestAnimationFrame(() => {
      const frame2 = el.closest(".cf-region");
      const region = frame2 ? REGIONS.get(frame2) : void 0;
      if (!region) {
        return;
      }
      const driver = {
        c,
        from
      };
      release = region.addDriver(driver);
      if (this.take === 0) {
        this.take = 1;
      }
      afterSettle(() => region.standOne(driver));
    });
    return () => {
      cancelAnimationFrame(id2);
      release();
    };
  });
  static {
    setComponentTemplate19(precompileTemplate19('\n    <span hidden data-take={{this.take}} {{this.hold @c (if @from @from "")}}></span>\n  ', {
      strictMode: true
    }), this);
  }
};
var Sound = class extends Component19 {
  cue = modifier12((el, [at2, from, kind, gain]) => {
    let release = () => {
    };
    const id2 = requestAnimationFrame(() => {
      const frame2 = el.closest(".cf-region");
      const region = frame2 ? REGIONS.get(frame2) : void 0;
      if (region) {
        release = region.addCue({
          at: at2,
          from,
          gain,
          kind
        });
      }
    });
    return () => {
      cancelAnimationFrame(id2);
      release();
    };
  });
  static {
    setComponentTemplate19(precompileTemplate19('\n    <span hidden {{this.cue @at (if @from @from "") @kind (if @gain @gain 1)}}></span>\n  ', {
      strictMode: true
    }), this);
  }
};
var RegionPicture = class extends Component19 {
  static {
    decorateFieldV2(this.prototype, "shotName", [tracked6], function() {
      return "";
    });
  }
  #shotName = (initializeDeferredDecorator(this, "shotName"), void 0);
  Drive = Drive;
  Sound = Sound;
  stageEl;
  frameEl;
  pose = {};
  pending = 0;
  get width() {
    return this.args.width ?? 1920;
  }
  get height() {
    return this.args.height ?? 1080;
  }
  /* ---- the sound --------------------------------------------------- */
  player = new TrackPlayer();
  cues = /* @__PURE__ */ new Set();
  voiceAt = [];
  total = 0;
  held = false;
  renderTimer = 0;
  rendered = "";
  addCue(c) {
    this.cues.add(c);
    this.soundLater();
    return () => {
      this.cues.delete(c);
      this.soundLater();
    };
  }
  /** re-render the track when the cues or the schedule settle */
  soundLater() {
    window.clearTimeout(this.renderTimer);
    this.renderTimer = window.setTimeout(() => void this.renderSound(), 250);
  }
  async renderSound() {
    if (!this.total || typeof OfflineAudioContext === "undefined") {
      return;
    }
    const cues2 = [...this.cues].map((c) => ({
      gain: c.gain,
      kind: c.kind,
      t: (c.from ? this.starts.get(c.from) ?? 0 : 0) + c.at
    }));
    const spec = {
      bed: this.args.bed ?? true,
      cues: cues2,
      total: this.total,
      voice: this.voiceAt
    };
    const key = JSON.stringify(spec);
    if (key === this.rendered) {
      return;
    }
    this.rendered = key;
    try {
      this.player.buffer = await renderTrack(spec);
      this.frameEl?.setAttribute("data-track", `${cues2.length}`);
    } catch {
      this.player.buffer = null;
      this.frameEl?.setAttribute("data-track", "failed");
    }
  }
  /* ---- the clock --------------------------------------------------- */
  t = this.args.poster ?? 0;
  starts = /* @__PURE__ */ new Map();
  drivers = /* @__PURE__ */ new Set();
  addDriver(d) {
    this.drivers.add(d);
    return () => this.drivers.delete(d);
  }
  /** stand one scene's run at the film's time */
  standOne(d) {
    const run = d.c.run;
    if (!run) {
      return;
    }
    const zero = d.from ? this.starts.get(d.from) ?? 0 : 0;
    const local = Math.max(0, Math.min(run.duration, this.t - zero));
    if (!run.paused) {
      run.pause();
    }
    if (Math.abs(run.time - local) > 1e-4) {
      run.time = local;
    }
  }
  standAll() {
    for (const d of this.drivers) {
      this.standOne(d);
    }
  }
  /** a named thing's box on the stage, as fractions of the stage */
  frameOf(name) {
    const stage = this.stageEl;
    const el = stage?.querySelector(`[data-frame="${CSS.escape(name)}"]`);
    if (!stage || !el) {
      return null;
    }
    const s = stage.getBoundingClientRect();
    const r = el.getBoundingClientRect();
    const k = s.width / this.width || 1;
    const x = (r.left - s.left) / k;
    const y = (r.top - s.top) / k;
    const w = r.width / k;
    const h = r.height / k;
    return {
      h: h / this.height,
      w: w / this.width,
      x: (x + w / 2) / this.width - 0.5,
      y: (y + h / 2) / this.height - 0.5
    };
  }
  /** the pose, as a frame: centre the stage point (x, y) and magnify */
  paint() {
    const frame2 = this.frameEl;
    const stage = this.stageEl;
    if (!frame2 || !stage) {
      return;
    }
    const cw = frame2.clientWidth;
    const ch = frame2.clientHeight;
    const fit = Math.max(cw / this.width, ch / this.height);
    const zoom = Math.max(0.05, this.pose.zoom ?? 1);
    const s = fit * zoom;
    const px2 = (0.5 + (this.pose.fx ?? 0)) * this.width;
    const py = (0.5 + (this.pose.lookY ?? 0)) * this.height;
    const tx = cw / 2 + (this.pose.ox ?? 0) * cw - px2 * s;
    const ty = ch / 2 + (this.pose.oy ?? 0) * ch - py * s;
    stage.style.width = `${this.width}px`;
    stage.style.height = `${this.height}px`;
    stage.style.background = this.args.paper ?? "transparent";
    stage.style.transform = `translate(${tx.toFixed(2)}px,${ty.toFixed(2)}px) scale(${s.toFixed(5)})`;
  }
  /* ---- the seams ------------------------------------------------------ */
  /**
  * THE STILL IS THE DOM. An iframe picture hands a seam a JPEG of its
  * canvas; a region has something better — its own stage, cloned. The
  * clone is the outgoing frame exactly, text and all, at the lens it was
  * framed through. Values Choreo holds in paused WAAPI animations are
  * not in the markup, so they are baked in from computed style first.
  */
  still;
  veilEl;
  hold(on5) {
    this.still?.remove();
    this.still = void 0;
    const stage = this.stageEl;
    const frame2 = this.frameEl;
    if (!on5 || !stage || !frame2) {
      return;
    }
    const clone = stage.cloneNode(true);
    const moving = new Set(stage.getAnimations({
      subtree: true
    }).map((a) => a.effect?.target).filter(Boolean));
    if (moving.size) {
      const a = document.createTreeWalker(stage, NodeFilter.SHOW_ELEMENT);
      const b = document.createTreeWalker(clone, NodeFilter.SHOW_ELEMENT);
      let x = a.currentNode;
      let y = b.currentNode;
      while (x && y) {
        if (moving.has(x)) {
          const cs = getComputedStyle(x);
          const st = y.style;
          st.transform = cs.transform;
          st.opacity = cs.opacity;
          st.clipPath = cs.clipPath;
          st.filter = cs.filter;
          st.backgroundColor = cs.backgroundColor;
          st.color = cs.color;
        }
        x = a.nextNode();
        y = b.nextNode();
      }
    }
    clone.classList.add("cf-region-still");
    clone.setAttribute("aria-hidden", "true");
    clone.style.pointerEvents = "none";
    frame2.appendChild(clone);
    this.still = clone;
  }
  /** a seam's progress on the still: the region's own four, and the film's mix */
  seamAt(spec) {
    const still = this.still;
    const veil = this.veilEl;
    if (!spec) {
      this.hold(false);
      if (veil) {
        veil.style.opacity = "0";
      }
      return;
    }
    if (veil) {
      veil.style.background = spec.color ?? "#0d0905";
      veil.style.opacity = `${spec.veil}`;
    }
    if (!still) {
      return;
    }
    const p = Math.max(0, Math.min(1, spec.p));
    const e = p < 0.5 ? 4 * p * p * p : 1 - (-2 * p + 2) ** 3 / 2;
    const base = this.stageEl?.style.transform ?? "";
    still.style.clipPath = "";
    still.style.filter = "";
    still.style.opacity = "1";
    switch (spec.name) {
      case "wipe":
        still.style.clipPath = `inset(0 0 0 ${(e * 100).toFixed(2)}%)`;
        break;
      case "iris":
        still.style.clipPath = `circle(${((1 - e) * 80).toFixed(2)}% at 50% 50%)`;
        break;
      case "blur":
        still.style.opacity = `${1 - e}`;
        still.style.filter = `blur(${(e * 24).toFixed(1)}px)`;
        break;
      case "zoom":
        still.style.opacity = `${1 - e}`;
        still.style.transform = `${base} scale(${1 + e * 0.35})`;
        still.style.transformOrigin = "50% 50%";
        return;
      default:
        still.style.opacity = `${spec.mix}`;
    }
    still.style.transform = base;
  }
  /* ---- the voice ------------------------------------------------------ */
  master = 1;
  soundOn = true;
  line = null;
  primed = /* @__PURE__ */ new Map();
  fadeOut(a, ms = 120) {
    const from = a.volume;
    const t0 = performance.now();
    const step = () => {
      const k = Math.min(1, (performance.now() - t0) / Math.max(1, ms));
      a.volume = from * (1 - k);
      if (k < 1) {
        window.setTimeout(step, 16);
      } else {
        a.pause();
      }
    };
    step();
  }
  /** the port: what the film calls; anything it names that a region has no use for is a no-op */
  port = (() => {
    const value = {
      dissolve: () => false,
      dur: 0,
      height: () => 12,
      looks: () => [],
      palette: () => ({
        accent: this.args.accent ?? "#f0673a",
        ink: this.args.ink ?? "#f3ece3",
        ink2: "#d2c9bf",
        ink3: "#b8aea3",
        paper: this.args.paper ?? "#2a2521",
        rule: "#4a4139",
        time: "#d2c9bf"
      }),
      perf: () => ({
        cap: 60,
        dpr: 1,
        frameMs: 8,
        pinned: null
      }),
      pose: (p) => {
        this.pose = {
          ...this.pose,
          ...p
        };
        this.paint();
      },
      project: () => ({
        on: false,
        x: 0,
        y: 0,
        z: 0
      }),
      rising: () => null,
      clock: (t, jumped) => {
        this.t = t;
        this.standAll();
        this.player.at(t, !this.held, jumped);
      },
      idle: (v) => {
        this.held = v;
        if (v) {
          this.player.pause();
        }
      },
      frame: (name) => this.frameOf(name),
      freeze: (on5) => this.hold(on5),
      seam: (spec) => this.seamAt(spec),
      schedule: (s) => {
        this.starts = new Map(s.beats.map((b) => [b.id, b.start]));
        this.total = s.total;
        this.voiceAt = s.voice ?? [];
        this.standAll();
        this.soundLater();
      },
      shot: (name) => {
        if (name !== this.shotName) {
          this.shotName = name;
        }
      },
      snapshot: () => "",
      sound: (on5) => {
        this.soundOn = on5;
        this.player.sound(on5);
        if (this.line) {
          this.line.volume = on5 ? this.master : 0;
        }
      },
      speaking: () => !!this.line && !this.line.paused && !this.line.ended,
      style: () => 0,
      styleIndex: () => 0,
      sun: () => ({
        h: this.height,
        on: false,
        w: this.width,
        x: this.width / 2,
        y: 0
      }),
      view: () => ({
        az: 0,
        el: 0,
        fov: 40,
        h: this.height,
        w: this.width,
        zoom: this.pose.zoom ?? 1
      }),
      volume: (v) => {
        this.master = v;
        if (this.line) {
          this.line.volume = this.soundOn ? v : 0;
        }
      },
      pause: (v) => {
        this.held = v;
        if (v) {
          this.player.pause();
        }
        const a = this.line;
        if (!a || a.ended) {
          return;
        }
        if (v) {
          a.pause();
        } else {
          void a.play().catch(() => {
          });
        }
      },
      voicePrime: (url) => {
        if (!this.primed.has(url)) {
          const a = new Audio();
          a.preload = "auto";
          a.src = url;
          this.primed.set(url, a);
        }
      },
      voice: (url, gain = 1, at2 = 0) => {
        if (this.line) {
          this.fadeOut(this.line);
        }
        const a = this.primed.get(url) ?? new Audio(url);
        this.primed.delete(url);
        a.currentTime = Math.max(0, at2 || 0);
        a.volume = this.soundOn ? Math.min(1, this.master * (gain ?? 1)) : 0;
        this.line = a;
        void a.play().catch(() => {
        });
      },
      voiceStop: (ms) => {
        if (this.line) {
          this.fadeOut(this.line, ms ?? 120);
        }
        this.line = null;
      }
    };
    const noop3 = () => {
    };
    return new Proxy(value, {
      get: (t, k) => k in t ? t[k] : noop3,
      has: () => true
    });
  })();
  get spec() {
    return {
      accent: {
        dark: this.args.accent ?? "#f0673a"
      },
      adjustments: {},
      assets: this.args.assets ?? "",
      lens: "2d",
      port: this.port,
      seams: ["wipe", "iris", "blur", "zoom"],
      src: "",
      standing: 0,
      title: this.args.title
    };
  }
  /** registers a frame after render, as IframePicture does */
  attach = modifier12((frame2) => {
    REGIONS.set(frame2, this);
    this.frameEl = frame2;
    this.stageEl = frame2.querySelector(".cf-region-stage");
    this.veilEl = frame2.querySelector(".cf-region-veil");
    const spec = this.spec;
    this.pending = requestAnimationFrame(() => {
      this.pending = 0;
      this.args.register(spec);
    });
    const ro = new ResizeObserver(() => this.paint());
    ro.observe(frame2);
    this.paint();
    return () => {
      ro.disconnect();
      if (this.pending) {
        cancelAnimationFrame(this.pending);
        this.pending = 0;
      }
      this.line?.pause();
      window.clearTimeout(this.renderTimer);
      this.player.destroy();
      this.args.register(null);
    };
  });
  static {
    setComponentTemplate19(precompileTemplate19('\n    <div class="cf-region" role="img" aria-label={{@title}} {{this.attach}} ...attributes>\n      <div class="cf-region-stage">\n        {{yield (hash Drive=this.Drive Sound=this.Sound shot=this.shotName)}}\n      </div>\n      <div class="cf-region-veil"></div>\n    </div>\n    <style>\n      .cf-region {\n        position: absolute;\n        inset: 0;\n        overflow: hidden;\n      }\n      .cf-region-still {\n        z-index: 2;\n      }\n      .cf-region-veil {\n        position: absolute;\n        inset: 0;\n        z-index: 3;\n        opacity: 0;\n        pointer-events: none;\n      }\n      .cf-region-stage {\n        position: absolute;\n        left: 0;\n        top: 0;\n        transform-origin: 0 0;\n        will-change: transform;\n      }\n    </style>\n  ', {
      strictMode: true,
      scope: () => ({
        hash: hash2
      })
    }), this);
  }
};

// dist/film/score.js
var METAL = [205.3, 304.4, 369.6, 522.7, 540, 800].map((f) => f * 1.7);
var OVERSAMPLE = 4;
var TAPS = 8;
var PHASES = Array.from({
  length: OVERSAMPLE - 1
}, (_, p) => {
  const frac = (p + 1) / OVERSAMPLE;
  return Float64Array.from({
    length: 2 * TAPS
  }, (_2, j) => {
    const d = frac - (j - TAPS + 1);
    return Math.sin(Math.PI * d) / (Math.PI * d) * 0.5 * (1 + Math.cos(Math.PI * d / TAPS));
  });
});

// dist/gestures/drag-controls.js
var DragControls = class {
  componentControls = /* @__PURE__ */ new Set();
  /**
   * Subscribe a component's internal `VisualElementDragControls` to the user-facing API.
   *
   * @internal
   */
  subscribe(controls) {
    this.componentControls.add(controls);
    return () => this.componentControls.delete(controls);
  }
  /**
   * Start a drag gesture on every `motion` component that has this set of drag controls
   * passed into it via the `dragControls` prop.
   *
   * ```jsx
   * dragControls.start(e, {
   *   snapToCursor: true
   * })
   * ```
   *
   * @param event - PointerEvent
   * @param options - Options
   *
   * @public
   */
  start(event, options) {
    this.componentControls.forEach((controls) => {
      controls.start(event, options);
    });
  }
  /**
   * Cancels a drag gesture.
   *
   * ```jsx
   * dragControls.cancel()
   * ```
   *
   * @public
   */
  cancel() {
    this.componentControls.forEach((controls) => {
      controls.cancel();
    });
  }
  /**
   * Stops a drag gesture.
   *
   * ```jsx
   * dragControls.stop()
   * ```
   *
   * @public
   */
  stop() {
    this.componentControls.forEach((controls) => {
      controls.stop();
    });
  }
};
var createDragControls = () => new DragControls();

// dist/gestures/transform-page-point.js
var resolve2 = (ref) => (ref && typeof ref === "object" && "current" in ref ? ref.current : ref) ?? null;
function correctParentTransform(parentRef) {
  return (point2) => {
    const parent = resolve2(parentRef);
    if (!parent) {
      return point2;
    }
    const inv = getInverseMatrix(parent);
    if (!inv) {
      return point2;
    }
    const rect2 = parent.getBoundingClientRect();
    const cx = rect2.left + window.scrollX + rect2.width / 2;
    const cy = rect2.top + window.scrollY + rect2.height / 2;
    const dx = point2.x - cx, dy = point2.y - cy;
    return {
      x: cx + inv.a * dx + inv.c * dy,
      y: cy + inv.b * dx + inv.d * dy
    };
  };
}
function getInverseMatrix(element) {
  const {
    transform
  } = getComputedStyle(element);
  if (!transform || transform === "none") {
    return null;
  }
  const match2 = transform.match(/^matrix3d\((.*)\)$/u) || transform.match(/^matrix\((.*)\)$/u);
  if (!match2) {
    return null;
  }
  const v = match2[1].split(",").map(Number);
  const is3d = transform.startsWith("matrix3d");
  const a = v[0], b = v[1], c = is3d ? v[4] : v[2], d = is3d ? v[5] : v[3];
  const det = a * d - b * c;
  if (Math.abs(det) < 1e-10) {
    return null;
  }
  return {
    a: d / det,
    b: -b / det,
    c: -c / det,
    d: a / det
  };
}
function transformViewBoxPoint(svgRef) {
  return (point2) => {
    const svg = resolve2(svgRef);
    if (!svg) {
      return point2;
    }
    const viewBox = svg.viewBox?.baseVal;
    if (!viewBox || viewBox.width === 0 && viewBox.height === 0) {
      return point2;
    }
    const bbox = svg.getBoundingClientRect();
    if (bbox.width === 0 || bbox.height === 0) {
      return point2;
    }
    const scaleX2 = viewBox.width / bbox.width, scaleY2 = viewBox.height / bbox.height;
    const svgX = bbox.left + window.scrollX, svgY = bbox.top + window.scrollY;
    return {
      x: (point2.x - svgX) * scaleX2 + svgX,
      y: (point2.y - svgY) * scaleY2 + svgY
    };
  };
}

// dist/helpers.js
function to(values = {}) {
  return values;
}
function styles(values = {}) {
  return values;
}
function perValue(values = {}) {
  return values;
}
function spring2(options = {}) {
  return {
    type: "spring",
    ...options
  };
}
function tween(options = {}) {
  return {
    type: "tween",
    ...options
  };
}
function inertia2(options = {}) {
  return {
    type: "inertia",
    ...options
  };
}
function ease2(x1, y1, x2, y2) {
  return [x1, y1, x2, y2];
}

// dist/presence.js
import { registerDestructor as registerDestructor3 } from "@ember/destroyable";
import Component20 from "@glimmer/component";
import { tracked as tracked7 } from "@glimmer/tracking";
import { precompileTemplate as precompileTemplate20 } from "@ember/template-compilation";
import { setComponentTemplate as setComponentTemplate20 } from "@ember/component";
var presenceId = 0;
var Entry = class {
  static {
    decorateFieldV2(this.prototype, "item", [tracked7]);
  }
  #item = (initializeDeferredDecorator(this, "item"), void 0);
  /** last presence seen by the diff — plain state, never read during render tracking */
  wasPresent = true;
  id = `presence-${presenceId++}`;
  children = /* @__PURE__ */ new Map();
  subscribers = /* @__PURE__ */ new Set();
  /** popLayout: the direct children, so they can be measured before the DOM changes */
  popCandidates = /* @__PURE__ */ new Set();
  subscribe(refresh) {
    this.subscribers.add(refresh);
    return () => this.subscribers.delete(refresh);
  }
  popCandidate(node) {
    this.popCandidates.add(node);
    return () => {
      this.popCandidates.delete(node);
    };
  }
  key;
  owner;
  initialBlocked;
  constructor(key, item, owner, initialBlocked) {
    this.key = key;
    this.item = item;
    this.owner = owner;
    this.initialBlocked = initialBlocked;
  }
  /** derived from @items (and the parent handle) — nothing is mutated during render */
  get isPresent() {
    return this.owner.isKeyPresent(this.key);
  }
  get mode() {
    return this.owner.args.mode ?? "sync";
  }
  get anchorX() {
    return this.owner.args.anchorX ?? "left";
  }
  get anchorY() {
    return this.owner.args.anchorY ?? "top";
  }
  get context() {
    return {
      id: this.id,
      isPresent: this.isPresent,
      initial: this.initialBlocked ? false : void 0,
      custom: this.owner.args.custom,
      register: (childId) => {
        const leaving = !this.isPresent;
        this.children.set(childId, leaving);
        if (leaving) {
          postRender(() => this.checkComplete());
        }
        return () => {
          this.children.delete(childId);
          if (!this.isPresent && !this.children.size) {
            this.owner.onExit(this.key);
          }
        };
      },
      onExitComplete: (childId) => {
        this.children.set(childId, true);
        this.checkComplete();
      }
    };
  }
  /** presence flipped (PresenceChild's isPresent effects): children report again; no children → done at once */
  presenceChanged(present) {
    if (!present && this.mode === "popLayout") {
      this.popCandidates.forEach((node) => node.measureForPop());
    }
    this.children.forEach((_, k) => this.children.set(k, false));
    postRender(() => this.notify());
    if (!present) {
      postRender(() => this.checkImmediateExit());
    }
  }
  notify() {
    flushPendingMounts();
    this.subscribers.forEach((fn3) => fn3());
  }
  /** every registered child has reported: the leaver is done */
  checkComplete() {
    if (this.isPresent) {
      return;
    }
    for (const done of this.children.values()) {
      if (!done) {
        return;
      }
    }
    this.owner.onExit(this.key);
  }
  checkImmediateExit() {
    flushPendingMounts();
    if (!this.isPresent && !this.children.size) {
      this.owner.onExit(this.key);
    }
  }
};
var Presence = class extends Component20 {
  entries = /* @__PURE__ */ new Map();
  order = [];
  lastItems;
  firstRender = true;
  /** React's exitComplete map + exitingComponents set */
  exitComplete = /* @__PURE__ */ new Map();
  exiting = /* @__PURE__ */ new Set();
  pendingItems = [];
  registeredWithParent;
  selfId = `presence:${presenceId++}`;
  static {
    decorateFieldV2(this.prototype, "version", [tracked7], function() {
      return 0;
    });
  }
  #version = (initializeDeferredDecorator(this, "version"), void 0);
  constructor(owner, args) {
    super(owner, args);
    registerDestructor3(this, () => this.registeredWithParent?.());
  }
  get parentPresent() {
    const {
      propagate,
      parent
    } = this.args;
    return !propagate || !parent || parent.isPresent;
  }
  /** the keys @items currently asks for (empty while a propagating parent is leaving) */
  get presentKeys() {
    return this.parentPresent ? this.args.items.map(this.args.key) : [];
  }
  isKeyPresent(key) {
    return this.presentKeys.includes(key);
  }
  /* note (ember/no-side-effects): AnimatePresence's diff of present vs rendered children runs
   during render; this getter is that render step (entries, order and exit bookkeeping are its output) */
  get rendered() {
    void this.version;
    const items = this.args.items;
    const parentPresent = this.parentPresent;
    if (this.args.propagate && this.args.parent && !this.registeredWithParent) {
      this.registeredWithParent = this.args.parent.context.register(this.selfId);
    }
    if (items !== this.lastItems || this.lastParentPresent !== parentPresent) {
      snapshotOnRender();
      this.lastItems = items;
      this.lastParentPresent = parentPresent;
      this.pendingItems = items;
      const presentKeys = this.presentKeys;
      const blockInitial = this.firstRender && this.args.initial === false;
      items.forEach((item) => {
        const k = this.args.key(item);
        const e = this.entries.get(k);
        if (e) {
          e.item = item;
        } else {
          this.entries.set(k, new Entry(k, item, this, blockInitial));
        }
      });
      const exitingKeys = [];
      let next2 = parentPresent ? [...presentKeys] : [];
      let insertionIndex = 0;
      for (const k of this.order) {
        const presentIndex = presentKeys.indexOf(k);
        if (presentIndex === -1) {
          next2.splice(insertionIndex++, 0, k);
          exitingKeys.push(k);
        } else {
          insertionIndex = presentIndex + exitingKeys.length + 1;
        }
      }
      if ((this.args.mode ?? "sync") === "wait" && exitingKeys.length) {
        next2 = exitingKeys;
      }
      this.order = next2.filter((k, i) => next2.indexOf(k) === i);
      for (const k of this.order) {
        const e = this.entries.get(k);
        const present = presentKeys.includes(k);
        if (!present) {
          if (this.exitComplete.get(k) !== true) {
            this.exitComplete.set(k, false);
          }
        } else {
          this.exitComplete.delete(k);
          this.exiting.delete(k);
        }
        if (e.wasPresent !== present) {
          e.wasPresent = present;
          e.presenceChanged(present);
        }
      }
      this.firstRender = false;
      if (this.args.propagate && !parentPresent && !this.order.length) {
        postRender(() => this.safeToRemove());
      }
    }
    return this.order.map((k) => this.entries.get(k));
  }
  /* end note */
  lastParentPresent;
  /** AnimatePresence's onExit for one child: once every exiting child is done, show what's pending */
  onExit(key) {
    if (this.exiting.has(key)) {
      return;
    }
    if (!this.exitComplete.has(key)) {
      return;
    }
    this.exiting.add(key);
    this.exitComplete.set(key, true);
    for (const done of this.exitComplete.values()) {
      if (!done) {
        return;
      }
    }
    const presentKeys = this.parentPresent ? this.pendingItems.map(this.args.key) : [];
    for (const k of this.order) {
      if (!presentKeys.includes(k)) {
        this.entries.delete(k);
      }
    }
    this.lastItems = void 0;
    this.exitComplete.clear();
    this.exiting.clear();
    this.order = presentKeys;
    this.version++;
    if (this.args.propagate) {
      this.safeToRemove();
    }
    this.args.onExitComplete?.();
  }
  safeToRemove() {
    this.args.parent?.context.onExitComplete?.(this.selfId);
  }
  static {
    setComponentTemplate20(precompileTemplate20('\n    {{#each this.rendered key="key" as |e|}}\n      {{yield e.item e}}\n    {{/each}}\n  ', {
      strictMode: true
    }), this);
  }
};

// dist/reorder/group.js
import Component21 from "@glimmer/component";
import { tracked as tracked8 } from "@glimmer/tracking";
import { consumeTag as consumeTag3, VOLATILE_TAG as VOLATILE_TAG3 } from "@glimmer/validator";

// dist/reorder/capture.js
import { modifier as modifier13 } from "ember-modifier";
var captureGroup = modifier13((el, [ref]) => {
  ref.current = el;
  return () => {
    ref.current = null;
  };
});

// dist/reorder/check-reorder.js
function checkReorder(order, value, offset, velocity, axis, direction = "ltr") {
  const index = order.findIndex((item2) => item2.value === value);
  if (index === -1) {
    return order;
  }
  if (axis === "xy") {
    const {
      layout
    } = order[index];
    const center = {
      x: mixNumber(layout.x.min, layout.x.max, 0.5) + offset.x,
      y: mixNumber(layout.y.min, layout.y.max, 0.5) + offset.y
    };
    const lines = getLines(order);
    const sourceLine = lines.find((line) => line.items.includes(order[index]));
    const targetLine = lines.reduce((closest, line) => distanceToLine(center.y, line) < distanceToLine(center.y, closest) ? line : closest);
    if (targetLine !== sourceLine) {
      return moveToLine(order, index, center.x, targetLine, direction);
    }
    const currentDistance = distanceToBox(center, layout);
    let target = -1;
    let targetDistance = currentDistance;
    order.forEach((item2, targetIndex) => {
      if (targetIndex === index) {
        return;
      }
      const distance2 = distanceToBox(center, item2.layout);
      if (distance2 < targetDistance) {
        target = targetIndex;
        targetDistance = distance2;
      }
    });
    return target === -1 ? order : moveItem(order, index, index + Math.sign(target - index));
  }
  if (!velocity[axis]) {
    return order;
  }
  const nextOffset = velocity[axis] > 0 ? 1 : -1;
  const nextItem = order[index + nextOffset];
  if (!nextItem) {
    return order;
  }
  const item = order[index];
  const itemLayout = item.layout[axis];
  const nextLayout = nextItem.layout[axis];
  const nextItemCenter = mixNumber(nextLayout.min, nextLayout.max, 0.5);
  if (nextOffset === 1 && itemLayout.max + offset[axis] > nextItemCenter || nextOffset === -1 && itemLayout.min + offset[axis] < nextItemCenter) {
    return moveItem(order, index, index + nextOffset);
  }
  return order;
}
function getLines(order) {
  const lines = [];
  order.forEach((item) => {
    const {
      min,
      max
    } = item.layout.y;
    const line = lines[lines.length - 1];
    if (!line || min >= line.max || max <= line.min) {
      lines.push({
        items: [item],
        min,
        max
      });
    } else {
      line.items.push(item);
      line.min = Math.min(line.min, min);
      line.max = Math.max(line.max, max);
    }
  });
  return lines;
}
function distanceToLine(y, line) {
  return y < line.min ? line.min - y : y > line.max ? y - line.max : 0;
}
function moveToLine(order, index, x, line, direction) {
  const remaining = order.filter((_, itemIndex) => itemIndex !== index);
  const before = line.items.find((item) => {
    const center = mixNumber(item.layout.x.min, item.layout.x.max, 0.5);
    return direction === "ltr" ? x < center : x > center;
  });
  const targetIndex = before ? remaining.indexOf(before) : remaining.indexOf(line.items[line.items.length - 1]) + 1;
  const nextOrder = [...remaining];
  nextOrder.splice(targetIndex, 0, order[index]);
  return nextOrder.every((item, itemIndex) => item === order[itemIndex]) ? order : nextOrder;
}
function distanceToBox(point2, box) {
  const x = Math.max(box.x.min - point2.x, 0, point2.x - box.x.max);
  const y = Math.max(box.y.min - point2.y, 0, point2.y - box.y.max);
  return x * x + y * y;
}

// dist/reorder/detect-axis.js
var isSeparated = (a, b) => a.max <= b.min || b.max <= a.min;
function detectAxis(layouts) {
  let x = false;
  let y = false;
  for (let i = 0; i < layouts.length; i++) {
    for (let j = i + 1; j < layouts.length; j++) {
      x ||= isSeparated(layouts[i].x, layouts[j].x);
      y ||= isSeparated(layouts[i].y, layouts[j].y);
      if (x && y) {
        return "xy";
      }
    }
  }
  return x ? "x" : "y";
}

// dist/reorder/group.js
import { precompileTemplate as precompileTemplate21 } from "@ember/template-compilation";
import { setComponentTemplate as setComponentTemplate21 } from "@ember/component";
var ReorderGroup = class extends Component21 {
  itemLayouts = /* @__PURE__ */ new Map();
  static {
    decorateFieldV2(this.prototype, "detectedAxis", [tracked8], function() {
      return "y";
    });
  }
  #detectedAxis = (initializeDeferredDecorator(this, "detectedAxis"), void 0);
  isReordering = false;
  groupRef = {
    current: null
  };
  get axis() {
    return this.args.axis || this.detectedAxis;
  }
  /** disable browser scroll anchoring: reordering would otherwise shift the scroll position mid-drag */
  get style() {
    return {
      overflowAnchor: "none",
      ...this.args.style
    };
  }
  /** React: every render prunes layouts of values no longer present */
  prune() {
    const valuesSet = new Set(this.args.values);
    this.itemLayouts.forEach((_, value) => {
      if (!valuesSet.has(value)) {
        this.itemLayouts.delete(value);
      }
    });
  }
  registerItem = (value, layout) => {
    this.prune();
    this.itemLayouts.set(value, layout);
    if (!this.args.axis) {
      const nextAxis = detectAxis(this.args.values.flatMap((v) => {
        const l = this.itemLayouts.get(v);
        return l ? [l] : [];
      }));
      if (nextAxis !== this.detectedAxis) {
        this.detectedAxis = nextAxis;
      }
    }
  };
  updateOrder = (item, offset, velocity) => {
    if (this.isReordering) {
      return;
    }
    this.prune();
    const values = this.args.values;
    const order = values.flatMap((value) => {
      const layout = this.itemLayouts.get(value);
      return layout ? [{
        value,
        layout
      }] : [];
    });
    const el = this.groupRef.current;
    const direction = el?.ownerDocument.defaultView?.getComputedStyle(el).direction === "rtl" ? "rtl" : "ltr";
    const newOrder = checkReorder(order, item, offset, velocity, this.axis, direction);
    if (order !== newOrder) {
      this.isReordering = true;
      const newValues = [...values];
      const measuredIndexes = order.map(({
        value
      }) => values.indexOf(value));
      newOrder.forEach(({
        value
      }, index) => {
        newValues[measuredIndexes[index]] = value;
      });
      this.args.onReorder(newValues);
      postRender(() => {
        this.isReordering = false;
      });
    }
  };
  get context() {
    return {
      axis: this.axis,
      registerItem: this.registerItem,
      updateOrder: this.updateOrder,
      groupRef: this.groupRef
    };
  }
  /** React's Reorder.Group re-renders every item on reorder, so each snapshots its layout before the
  *  DOM moves — that snapshot is what lets the projection keep the dragged item under the pointer */
  get renderDetector() {
    consumeTag3(VOLATILE_TAG3);
    snapshotOnRender();
    return void 0;
  }
  static {
    setComponentTemplate21(precompileTemplate21("\n    {{this.renderDetector}}\n    <ul ...attributes {{captureGroup this.groupRef}} {{motion style=this.style layout=@layout transition=@transition}}>\n      {{yield this.context}}\n    </ul>\n  ", {
      strictMode: true,
      scope: () => ({
        captureGroup,
        motion: MotionModifier
      })
    }), this);
  }
};

// dist/reorder/item.js
import Component22 from "@glimmer/component";

// dist/reorder/auto-scroll.js
var threshold = 50;
var maxSpeed = 25;
var overflowStyles2 = /* @__PURE__ */ new Set(["auto", "scroll"]);
var initialScrollLimits = /* @__PURE__ */ new WeakMap();
var activeScrollEdge = /* @__PURE__ */ new WeakMap();
var currentGroupElement = null;
function resetAutoScrollState() {
  if (currentGroupElement) {
    const scrollableAncestor = findScrollableAncestor(currentGroupElement, "y");
    if (scrollableAncestor) {
      activeScrollEdge.delete(scrollableAncestor);
      initialScrollLimits.delete(scrollableAncestor);
    }
    const scrollableAncestorX = findScrollableAncestor(currentGroupElement, "x");
    if (scrollableAncestorX && scrollableAncestorX !== scrollableAncestor) {
      activeScrollEdge.delete(scrollableAncestorX);
      initialScrollLimits.delete(scrollableAncestorX);
    }
    currentGroupElement = null;
  }
}
function isScrollableElement(element, axis) {
  const style2 = getComputedStyle(element);
  const overflow = axis === "x" ? style2.overflowX : style2.overflowY;
  const isDocumentScroll = element === document.body || element === document.documentElement;
  return overflowStyles2.has(overflow) || isDocumentScroll;
}
function findScrollableAncestor(element, axis) {
  let current2 = element?.parentElement;
  while (current2) {
    if (isScrollableElement(current2, axis)) {
      return current2;
    }
    current2 = current2.parentElement;
  }
  return null;
}
function getScrollAmount(pointerPosition, scrollElement, axis) {
  const rect2 = scrollElement.getBoundingClientRect();
  const start2 = axis === "x" ? Math.max(0, rect2.left) : Math.max(0, rect2.top);
  const end = axis === "x" ? Math.min(window.innerWidth, rect2.right) : Math.min(window.innerHeight, rect2.bottom);
  const distanceFromStart = pointerPosition - start2;
  const distanceFromEnd = end - pointerPosition;
  if (distanceFromStart < threshold) {
    const intensity = 1 - distanceFromStart / threshold;
    return {
      amount: -maxSpeed * intensity * intensity,
      edge: "start"
    };
  } else if (distanceFromEnd < threshold) {
    const intensity = 1 - distanceFromEnd / threshold;
    return {
      amount: maxSpeed * intensity * intensity,
      edge: "end"
    };
  }
  return {
    amount: 0,
    edge: null
  };
}
function autoScrollIfNeeded(groupElement, pointerPosition, axis, velocity) {
  if (!groupElement) {
    return;
  }
  currentGroupElement = groupElement;
  const scrollableAncestor = findScrollableAncestor(groupElement, axis);
  if (!scrollableAncestor) {
    return;
  }
  const viewportPointerPosition = pointerPosition - (axis === "x" ? window.scrollX : window.scrollY);
  const {
    amount: scrollAmount,
    edge
  } = getScrollAmount(viewportPointerPosition, scrollableAncestor, axis);
  if (edge === null) {
    activeScrollEdge.delete(scrollableAncestor);
    initialScrollLimits.delete(scrollableAncestor);
    return;
  }
  const currentActiveEdge = activeScrollEdge.get(scrollableAncestor);
  const isDocumentScroll = scrollableAncestor === document.body || scrollableAncestor === document.documentElement;
  if (currentActiveEdge !== edge) {
    const shouldStart = edge === "start" && velocity < 0 || edge === "end" && velocity > 0;
    if (!shouldStart) {
      return;
    }
    activeScrollEdge.set(scrollableAncestor, edge);
    const maxScroll = axis === "x" ? scrollableAncestor.scrollWidth - (isDocumentScroll ? window.innerWidth : scrollableAncestor.clientWidth) : scrollableAncestor.scrollHeight - (isDocumentScroll ? window.innerHeight : scrollableAncestor.clientHeight);
    initialScrollLimits.set(scrollableAncestor, maxScroll);
  }
  if (scrollAmount > 0) {
    const initialLimit = initialScrollLimits.get(scrollableAncestor);
    const currentScroll = axis === "x" ? isDocumentScroll ? window.scrollX : scrollableAncestor.scrollLeft : isDocumentScroll ? window.scrollY : scrollableAncestor.scrollTop;
    if (currentScroll >= initialLimit) {
      return;
    }
  }
  if (axis === "x") {
    if (isDocumentScroll) {
      window.scrollBy({
        left: scrollAmount
      });
    } else {
      scrollableAncestor.scrollLeft += scrollAmount;
    }
  } else {
    if (isDocumentScroll) {
      window.scrollBy({
        top: scrollAmount
      });
    } else {
      scrollableAncestor.scrollTop += scrollAmount;
    }
  }
}

// dist/reorder/item.js
import { precompileTemplate as precompileTemplate22 } from "@ember/template-compilation";
import { setComponentTemplate as setComponentTemplate22 } from "@ember/component";
var ReorderItem = class extends Component22 {
  point = {
    x: isMotionValue(this.args.style?.["x"]) ? this.args.style["x"] : motionValue(0),
    y: isMotionValue(this.args.style?.["y"]) ? this.args.style["y"] : motionValue(0)
  };
  zIndex = transformValue(() => this.point.x.get() || this.point.y.get() ? 1 : "unset");
  get style() {
    return {
      ...this.args.style,
      x: this.point.x,
      y: this.point.y,
      zIndex: this.zIndex
    };
  }
  get layout() {
    return this.args.layout ?? true;
  }
  get dragAxis() {
    const {
      axis
    } = this.args.group;
    return axis === "xy" ? true : axis;
  }
  onDrag = (event, info) => {
    const {
      axis,
      updateOrder,
      groupRef
    } = this.args.group;
    const {
      velocity,
      point: pointerPoint
    } = info;
    const offset = {
      x: this.point.x.get(),
      y: this.point.y.get()
    };
    updateOrder(this.args.value, offset, velocity);
    const scrollAxis = axis === "xy" ? Math.abs(velocity.x) > Math.abs(velocity.y) ? "x" : "y" : axis;
    autoScrollIfNeeded(groupRef.current, pointerPoint[scrollAxis], scrollAxis, velocity[scrollAxis]);
    this.args.onDrag?.(event, info);
  };
  onDragEnd = (event, info) => {
    resetAutoScrollState();
    this.args.onDragEnd?.(event, info);
  };
  onLayoutMeasure = (measured) => this.args.group.registerItem(this.args.value, measured);
  static {
    setComponentTemplate22(precompileTemplate22("\n    <li ...attributes {{motion drag=this.dragAxis dragSnapToOrigin=true style=this.style layout=this.layout onDrag=this.onDrag onDragEnd=this.onDragEnd onLayoutMeasure=this.onLayoutMeasure initial=@initial animate=@animate exit=@exit whileDrag=@whileDrag transition=@transition dragTransition=@dragTransition dragListener=@dragListener dragControls=@dragControls presence=@presence}}>\n      {{yield}}\n    </li>\n  ", {
      strictMode: true,
      scope: () => ({
        motion: MotionModifier
      })
    }), this);
  }
};

// dist/scroll.js
import { tracked as tracked9 } from "@glimmer/tracking";
import { modifier as modifier14 } from "ember-modifier";
function scrollProgress(options = {}) {
  const values = {
    scrollX: motionValue(0),
    scrollY: motionValue(0),
    scrollXProgress: motionValue(0),
    scrollYProgress: motionValue(0)
  };
  let container, target;
  let stop;
  let attached = 0;
  const start2 = () => {
    stop?.();
    stop = scroll((_progress, {
      x,
      y
    }) => {
      values.scrollX.set(x.current);
      values.scrollXProgress.set(x.progress);
      values.scrollY.set(y.current);
      values.scrollYProgress.set(y.progress);
    }, {
      ...options,
      container,
      target
    });
  };
  const end = () => {
    stop?.();
    stop = void 0;
  };
  const attach = (set) => modifier14((el) => {
    set(el);
    attached++;
    start2();
    return () => {
      set(void 0);
      if (--attached) {
        start2();
      } else {
        end();
      }
    };
  });
  return {
    ...values,
    container: attach((el) => {
      container = el;
    }),
    target: attach((el) => {
      target = el;
    }),
    track: attach(() => {
    }),
    start: start2,
    stop: end
  };
}
var InView = class {
  static {
    decorateFieldV2(this.prototype, "isInView", [tracked9]);
  }
  #isInView = (initializeDeferredDecorator(this, "isInView"), void 0);
  options;
  constructor(options = {}) {
    this.options = options;
    this.isInView = options.initial ?? false;
  }
  observe = modifier14((el) => {
    const {
      root,
      margin,
      amount,
      once = false
    } = this.options;
    if (once && this.isInView) {
      return;
    }
    return inView(el, () => {
      this.isInView = true;
      return once ? void 0 : () => {
        this.isInView = false;
      };
    }, {
      root: (root && "current" in root ? root.current : root) || void 0,
      margin,
      amount
    });
  });
};
var useScroll = scrollProgress;
var useInView = (options) => new InView(options);

// dist/view-transition.js
import { join as join3, schedule as schedule5 } from "@ember/runloop";
function animateView2(update, options) {
  return animateView(async () => {
    await apply(update);
  }, options);
}
async function viewTransition(update, root) {
  if (prefersReducedMotion2()) {
    await apply(update);
    return;
  }
  const host = resolveHost(root);
  if (!host) {
    await apply(update);
    return;
  }
  try {
    await host.startViewTransition(() => apply(update)).finished;
  } catch {
  }
}
function resolveHost(root) {
  if (isHost(root)) {
    return root;
  }
  if (typeof document === "undefined") {
    return null;
  }
  if (isHost(document.body)) {
    return document.body;
  }
  if (isHost(document)) {
    return document;
  }
  return null;
}
function isHost(value) {
  return !!value && typeof value.startViewTransition === "function";
}
async function apply(update) {
  await new Promise((resolve3, reject) => {
    join3(() => {
      Promise.resolve(update()).then(resolve3, reject);
    });
  });
  await afterRender();
}
function afterRender() {
  return new Promise((resolve3) => {
    schedule5("afterRender", null, resolve3);
  });
}
function prefersReducedMotion2() {
  return typeof matchMedia === "function" && matchMedia("(prefers-reduced-motion: reduce)").matches;
}
export {
  Choreo,
  DragControls,
  EASINGS,
  Film,
  InView,
  LayoutGroup,
  Lyric,
  MotionConfig,
  MotionModifier,
  MotionNode,
  Presence,
  Reel,
  ReelChrome,
  ReelLayer,
  ReelScene,
  RegionPicture,
  ReorderGroup,
  ReorderItem,
  StepComponent,
  after,
  afterSettle,
  animateView2 as animateView,
  appliedCamera,
  at,
  beacon,
  choreoHostAt,
  choreoHostById,
  closestChoreo,
  closestLayoutGroup,
  closestMotionConfig,
  correctParentTransform,
  createArming,
  createDragControls,
  ease2 as ease,
  easeIn2 as easeIn,
  easeInAndOut,
  easeOut2 as easeOut,
  flushPendingMounts,
  inView,
  inertia2 as inertia,
  instantLayoutTransition,
  layoutChange,
  layoutLoopDetected,
  MotionModifier as motion,
  motionSpeed,
  onMotionSpeed,
  perValue,
  postRender,
  prepareThrough,
  requestSettle,
  resetLayoutLoopGuard,
  resolveEase,
  sampleThrough,
  scaleTransition,
  scroll,
  scrollInfo,
  scrollProgress,
  setMotionSpeed,
  setPostRender,
  shake,
  snapshotAll,
  snapshotOnRender,
  spring2 as spring,
  stagger,
  styles,
  to,
  toLocal,
  toMs,
  toPage,
  transformViewBoxPoint,
  tween,
  useInView,
  useScroll,
  viewTransition,
  zoomEase
};
