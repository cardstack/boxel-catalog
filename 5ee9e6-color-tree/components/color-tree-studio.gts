// =============================================================================
// ColorTreeStudio — the room the specimen is held in, as a reusable glimmer
// component: tumble the solid, slice it open (HUE leaf / VALUE plane), open
// the atlas (the same voxels laid flat as a page), morph between Munsell's
// measured tree and Itten's idealized sphere, and pick colors straight off
// the canvas. ColorTreeField's edit format renders this component — the
// studio itself owns no field state; picks flow out through @onPick and the
// current selection flows in through @color / @munsell. All WebGL work
// lives in utils/tree-engine.
// =============================================================================
import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { guidFor } from '@ember/object/internals';
import { modifier } from 'ember-modifier';
import { cn, cssVar, eq } from '@cardstack/boxel-ui/helpers';
import { Button, IconButton, Swatch } from '@cardstack/boxel-ui/components';
import EyeIcon from '@cardstack/boxel-icons/eye';
import EyeOffIcon from '@cardstack/boxel-icons/eye-off';
import { debounce } from 'lodash';
import { HUE_TIERS, hueLabel } from '../utils/munsell';
import { TreeEngine } from '../utils/tree-engine';

export interface ColorTreeStudioSignature {
  Args: {
    /* current selection, shown in the panel's picked chip */
    color?: string | null;
    munsell?: string | null;
    /* called (debounced) when the user picks a chip off the open atlas */
    onPick?: (hex: string, notation: string) => void;
    /* bounded height + panel closed by default, for field edit format */
    compact?: boolean;
  };
  Element: HTMLElement;
}

/* ═══════════════════════════════════════════════════════════════════════════
   STUDIO — the room the specimen is held in
   ═══════════════════════════════════════════════════════════════════════════ */
export class ColorTreeStudio extends Component<ColorTreeStudioSignature> {
  /* the studio is a field edit format, so several can share one page —
     ids must be instance-scoped or the labels cross-wire */
  uid = `ct-${guidFor(this)}`;

  @tracked densityIdx = 1;
  @tracked sliceMode = 0; // 0 off · 1 hue · 2 value
  @tracked morphed = false; // false = Munsell tree · true = Itten sphere
  @tracked paused = false;
  @tracked slicePos = 50;
  @tracked chromaPos = 100;
  @tracked glowPos = 50;
  @tracked contrastPos = 0;
  @tracked toast = '';
  @tracked panelOpen = !this.args.compact;
  @tracked miniOpen = true;
  /* untracked mirror of miniOpen — setupScene must read this one, or the
     autotracking modifier would tear down and rebuild the engine on every
     toggle */
  miniPref = true;
  @tracked turnPos = 15;
  @tracked chipCount = 0;
  @tracked soundOn = false;
  @tracked morphState = 'tree measured';
  @tracked gyroOn = false;
  @tracked gyroAvailable =
    typeof window !== 'undefined' &&
    'ontouchstart' in window &&
    !!window.DeviceOrientationEvent;
  audioCtx?: AudioContext;
  masterGain?: GainNode;
  padLP?: BiquadFilterNode;
  padOsc2?: OscillatorNode;
  glisOsc?: OscillatorNode;
  glisGain?: GainNode;
  sliceOsc?: OscillatorNode;
  sliceLP?: BiquadFilterNode;
  sliceGain?: GainNode;
  padTimer = 0;
  morphTimer = 0;
  ptrs = new Map<number, { x: number; y: number }>();
  lastPinch: number | null = null;
  holdTimer = 0;
  holdFired = false;
  layerKey = -1;
  gLast: { a: number; b: number } | null = null;
  engine?: TreeEngine;

  /* rapid picking shouldn't hammer the owner with saves — the last
     selection within 300ms is the one that's kept */
  saveSelection = debounce((hex: string, notation: string) => {
    this.args.onPick?.(hex, notation);
  }, 300);

  /* ---------------------------- audio ----------------------------------
     The signature texture: a gallery at night. A low room tone of filtered
     noise and three quiet sines in an open fifth — the pad of a place where
     color is kept — playing the moment sound is on, in any view. The chroma
     dial and the camera's approach open the pad's filter the way a skylight
     opens a room; the contrast dial detunes the middle voice so complements
     beat gently; the morph plays a slow glissando on the voxels' own clock;
     the atlas carries a tenor voice that tracks the open page. */
  toggleSound = () => {
    if (!this.audioCtx) {
      try {
        this.buildAudioGraph();
      } catch {
        return;
      }
    }
    this.soundOn = !this.soundOn;
    let ctx = this.audioCtx!;
    if (ctx.state === 'suspended') {
      ctx.resume();
    }
    this.masterGain!.gain.setTargetAtTime(
      this.soundOn ? 0.5 : 0,
      ctx.currentTime,
      0.6,
    );
    this.updateSliceSound();
  };

  buildAudioGraph() {
    let Ctor =
      window.AudioContext ??
      (window as unknown as { webkitAudioContext: typeof AudioContext })
        .webkitAudioContext;
    let ctx = new Ctor();
    this.audioCtx = ctx;
    let master = ctx.createGain();
    master.gain.value = 0;
    master.connect(ctx.destination);
    this.masterGain = master;

    // room tone: a 2s loop of integrated noise, kept below 160 Hz
    let len = ctx.sampleRate * 2;
    let nbuf = ctx.createBuffer(1, len, ctx.sampleRate);
    let data = nbuf.getChannelData(0);
    let last = 0;
    for (let i = 0; i < len; i++) {
      let w = Math.random() * 2 - 1;
      last = (last + 0.02 * w) / 1.02;
      data[i] = last * 3.2;
    }
    let nsrc = ctx.createBufferSource();
    nsrc.buffer = nbuf;
    nsrc.loop = true;
    let nlp = ctx.createBiquadFilter();
    nlp.type = 'lowpass';
    nlp.frequency.value = 160;
    nlp.Q.value = 0.4;
    let ngain = ctx.createGain();
    ngain.gain.value = 0.1;
    nsrc.connect(nlp);
    nlp.connect(ngain);
    ngain.connect(master);
    nsrc.start();

    // pad: three sines in an open fifth behind a slowly breathing filter
    let padLP = ctx.createBiquadFilter();
    padLP.type = 'lowpass';
    padLP.frequency.value = 520;
    padLP.Q.value = 0.6;
    let padGain = ctx.createGain();
    padGain.gain.value = 0.11;
    padLP.connect(padGain);
    padGain.connect(master);
    [110, 164.81, 220].forEach((f, i) => {
      let o = ctx.createOscillator();
      o.type = 'sine';
      o.frequency.value = f;
      let g = ctx.createGain();
      g.gain.value = i === 2 ? 0.5 : 0.85;
      o.connect(g);
      g.connect(padLP);
      o.start();
      if (i === 1) {
        this.padOsc2 = o;
      }
    });
    this.padLP = padLP;
    let lfo = ctx.createOscillator();
    lfo.type = 'sine';
    lfo.frequency.value = 0.07;
    let lfoGain = ctx.createGain();
    lfoGain.gain.value = 110;
    lfo.connect(lfoGain);
    lfoGain.connect(padLP.frequency);
    lfo.start();

    // glissando voice for the morph
    let glisOsc = ctx.createOscillator();
    glisOsc.type = 'sine';
    glisOsc.frequency.value = 329.63;
    let glisGain = ctx.createGain();
    glisGain.gain.value = 0;
    let glp = ctx.createBiquadFilter();
    glp.type = 'lowpass';
    glp.frequency.value = 900;
    glisOsc.connect(glisGain);
    glisGain.connect(glp);
    glp.connect(master);
    glisOsc.start();
    this.glisOsc = glisOsc;
    this.glisGain = glisGain;

    // slice voice: a steady tenor that tracks the open atlas page —
    // pitch climbs with the value disc, filter warms with the hue leaf
    let sliceOsc = ctx.createOscillator();
    sliceOsc.type = 'sawtooth';
    sliceOsc.frequency.value = 220;
    let sliceLP = ctx.createBiquadFilter();
    sliceLP.type = 'lowpass';
    sliceLP.frequency.value = 700;
    sliceLP.Q.value = 3.2;
    let sliceGain = ctx.createGain();
    sliceGain.gain.value = 0;
    sliceOsc.connect(sliceLP);
    sliceLP.connect(sliceGain);
    sliceGain.connect(master);
    sliceOsc.start();
    this.sliceOsc = sliceOsc;
    this.sliceLP = sliceLP;
    this.sliceGain = sliceGain;

    this.padTimer = window.setInterval(() => this.modulatePad(), 400);
  }

  /* chroma opens the filter the way a skylight opens a room; approaching
     the specimen brightens it further */
  modulatePad() {
    if (!this.audioCtx || !this.soundOn || !this.padLP) {
      return;
    }
    let near = this.engine
      ? Math.max(0, Math.min(1, (70 - this.engine.dist) / 52))
      : 0;
    let cut = 300 + (this.chromaPos / 100) * 700 + near * 500;
    this.padLP.frequency.setTargetAtTime(cut, this.audioCtx.currentTime, 0.5);
  }

  /* a slow E4↔B4 glide on the same clock the voxels travel by */
  playGliss(up: boolean) {
    if (!this.audioCtx || !this.soundOn || !this.glisOsc || !this.glisGain) {
      return;
    }
    let t = this.audioCtx.currentTime;
    this.glisOsc.frequency.setValueAtTime(up ? 329.63 : 493.88, t);
    this.glisOsc.frequency.setTargetAtTime(up ? 493.88 : 329.63, t, 0.5);
    this.glisGain.gain.setTargetAtTime(0.06, t, 0.4);
    this.glisGain.gain.setTargetAtTime(0, t + 1.0, 0.8);
  }

  /* value mode: v 1..9 → ~2.3 octaves of pitch. Hue mode: warmth =
     cos(angle around the wheel), warm leaves open the filter, cool ones
     close it, with a slight pitch drift so each leaf has its own centre.
     Silent whenever the atlas is closed or sound is off. */
  updateSliceSound() {
    if (!this.audioCtx || !this.sliceOsc || !this.sliceLP || !this.sliceGain) {
      return;
    }
    let t = this.audioCtx.currentTime;
    if (!this.soundOn || this.sliceMode === 0) {
      this.sliceGain.gain.setTargetAtTime(0, t, 0.35);
      return;
    }
    if (this.sliceMode === 2) {
      let v = 1 + Math.min(8, Math.floor((this.slicePos / 100) * 9));
      let f = 130 * Math.pow(2, ((v - 1) / 8) * 2.3);
      this.sliceOsc.frequency.setTargetAtTime(f, t, 0.08);
      this.sliceLP.frequency.setTargetAtTime(1100, t, 0.2);
      this.sliceLP.Q.setTargetAtTime(2.4, t, 0.2);
      this.sliceGain.gain.setTargetAtTime(0.055, t, 0.15);
    } else {
      let leaves = HUE_TIERS[this.densityIdx] / 2;
      let p = this.slicePos / 100;
      let j = Math.floor((((p % 1) + 1) % 1) * leaves) % leaves;
      let angle = (j / leaves) * Math.PI * 2;
      let warmth = Math.cos(angle);
      let cutoff = 380 * Math.pow(2, (warmth + 1) * 1.6);
      let pitch = 196 * Math.pow(2, warmth * 0.12);
      this.sliceOsc.frequency.setTargetAtTime(pitch, t, 0.18);
      this.sliceLP.frequency.setTargetAtTime(cutoff, t, 0.25);
      this.sliceLP.Q.setTargetAtTime(warmth > 0 ? 4.0 : 6.5, t, 0.25);
      this.sliceGain.gain.setTargetAtTime(0.048, t, 0.25);
    }
  }

  /* a small acknowledgment when a color is taken: two quick sine notes a
     fifth apart, soft attack, fast decay — a glass tap */
  copyChime() {
    if (!this.audioCtx || !this.soundOn || !this.masterGain) {
      return;
    }
    let ctx = this.audioCtx;
    let master = this.masterGain;
    let t = ctx.currentTime;
    for (let [f, d] of [
      [1318.51, 0],
      [1975.53, 0.07],
    ]) {
      let o = ctx.createOscillator();
      o.type = 'sine';
      o.frequency.value = f;
      let og = ctx.createGain();
      og.gain.value = 0;
      o.connect(og);
      og.connect(master);
      og.gain.setValueAtTime(0, t + d);
      og.gain.linearRampToValueAtTime(0.09, t + d + 0.012);
      og.gain.setTargetAtTime(0, t + d + 0.04, 0.09);
      o.start(t + d);
      o.stop(t + d + 0.7);
    }
  }

  dragging = false;
  lastX = 0;
  lastY = 0;
  moved = 0;
  toastTimer = 0;
  @tracked pickFx: { id: number; x: number; y: number; hex: string } | null =
    null;
  pickFxId = 0;
  pickFxTimer = 0;

  setupScene = modifier((canvas: HTMLCanvasElement) => {
    let engine = new TreeEngine(canvas);
    engine.showMini = this.miniPref;
    this.engine = engine;
    this.chipCount = engine.arrays.cfr.length;
    let onResize = () => engine.resize();
    window.addEventListener('resize', onResize);
    let ro = new ResizeObserver(onResize);
    ro.observe(canvas);
    return () => {
      window.removeEventListener('resize', onResize);
      window.removeEventListener('deviceorientation', this.onGyro);
      clearTimeout(this.holdTimer);
      clearTimeout(this.morphTimer);
      clearTimeout(this.pickFxTimer);
      clearTimeout(this.toastTimer);
      this.saveSelection.flush();
      clearInterval(this.padTimer);
      this.audioCtx?.close?.();
      this.audioCtx = undefined;
      this.masterGain = undefined;
      this.padLP = undefined;
      this.padOsc2 = undefined;
      this.glisOsc = undefined;
      this.glisGain = undefined;
      this.sliceOsc = undefined;
      this.sliceLP = undefined;
      this.sliceGain = undefined;
      this.soundOn = false;
      ro.disconnect();
      engine.dispose();
      this.engine = undefined;
    };
  });

  showToast = (msg: string, ms = 1800) => {
    this.toast = msg;
    clearTimeout(this.toastTimer);
    this.toastTimer = window.setTimeout(() => (this.toast = ''), ms);
  };

  dismissToast = () => {
    clearTimeout(this.toastTimer);
    this.toast = '';
  };

  onPointerDown = (evt: Event) => {
    let e = evt as PointerEvent;
    this.ptrs.set(e.pointerId, { x: e.clientX, y: e.clientY });
    this.dragging = true;
    this.moved = 0;
    this.lastX = e.clientX;
    this.lastY = e.clientY;
    this.lastPinch = null;
    this.holdFired = false;
    clearTimeout(this.holdTimer);
    if (this.sliceMode !== 0) {
      // hold-to-copy: press and hold any point on the open page for 450ms
      let cx = e.clientX;
      let cy = e.clientY;
      this.holdTimer = window.setTimeout(() => {
        if (!this.dragging || this.moved > 6) {
          return;
        }
        this.holdFired = true;
        this.pickAt(cx, cy);
      }, 450);
    }
    (e.target as HTMLElement).setPointerCapture?.(e.pointerId);
  };

  onPointerMove = (evt: Event) => {
    let e = evt as PointerEvent;
    if (!this.dragging || !this.engine) {
      return;
    }
    if (this.ptrs.has(e.pointerId)) {
      this.ptrs.set(e.pointerId, { x: e.clientX, y: e.clientY });
    }
    if (this.ptrs.size >= 2) {
      // pinch to approach: two fingers change the camera's distance
      let [p1, p2] = [...this.ptrs.values()];
      let d = Math.hypot(p1.x - p2.x, p1.y - p2.y);
      if (this.lastPinch != null) {
        this.engine.zoom((this.lastPinch - d) * 0.12);
      }
      this.lastPinch = d;
      this.moved += 10;
      return;
    }
    let dx = e.clientX - this.lastX;
    let dy = e.clientY - this.lastY;
    this.moved += Math.abs(dx) + Math.abs(dy);
    this.lastX = e.clientX;
    this.lastY = e.clientY;
    if (this.sliceMode !== 0) {
      // while reading the atlas, the drag scrubs pages instead of tumbling
      let p = this.slicePos / 100;
      if (this.sliceMode === 2) {
        p = Math.max(0, Math.min(1, p - dy / (window.innerHeight * 0.8)));
      } else {
        p = (((p + dx / window.innerWidth) % 1) + 1) % 1;
      }
      this.slicePos = p * 100;
      this.applyScan();
      return;
    }
    this.engine.tumble(dx, dy);
  };

  onPointerUp = (evt: Event) => {
    let e = evt as PointerEvent;
    clearTimeout(this.holdTimer);
    this.ptrs.delete(e.pointerId);
    if (this.ptrs.size > 0) {
      this.lastPinch = null;
      return;
    }
    let wasDrag = this.moved > 6;
    this.dragging = false;
    if (wasDrag || !this.engine || this.holdFired) {
      this.holdFired = false;
      return;
    }
    this.pickAt(e.clientX, e.clientY);
  };

  pickAt(cx: number, cy: number) {
    if (!this.engine) {
      return;
    }
    let picked = this.engine.pickHex(cx, cy);
    if (!picked) {
      return;
    }
    this.spawnPickFx(cx, cy, picked.hex);
    this.saveSelection(picked.hex, picked.notation);
    try {
      navigator.clipboard?.writeText(picked.hex);
      this.copyChime();
      this.showToast(`${picked.hex} copied · ${picked.notation}`);
    } catch {
      this.showToast(`${picked.hex} · ${picked.notation}`);
    }
  }

  /* a brief pulse of the taken color, blooming from the picked spot —
     the visual half of the copy acknowledgment (the chime is the other) */
  spawnPickFx(cx: number, cy: number, hex: string) {
    let rect = this.engine?.canvas.getBoundingClientRect();
    if (!rect) {
      return;
    }
    this.pickFx = {
      id: this.pickFxId++,
      x: cx - rect.left,
      y: cy - rect.top,
      hex,
    };
    clearTimeout(this.pickFxTimer);
    this.pickFxTimer = window.setTimeout(() => (this.pickFx = null), 750);
  }

  /* px units are attached here so the template can hand the values straight
     to the cssVar helper, which emits custom properties verbatim */
  get pickFxList() {
    let fx = this.pickFx;
    return fx ? [{ ...fx, cssX: `${fx.x}px`, cssY: `${fx.y}px` }] : [];
  }

  onWheel = (evt: Event) => {
    let e = evt as WheelEvent;
    e.preventDefault();
    this.engine?.zoom(e.deltaY * 0.03);
  };

  onDblClick = () => {
    this.engine?.refit();
  };

  setDensity = (idx: number) => {
    this.densityIdx = idx;
    this.engine?.setDensity(idx);
    if (this.engine) {
      this.chipCount = this.engine.arrays.cfr.length;
    }
    this.updateSliceSound();
  };

  togglePanel = () => {
    this.panelOpen = !this.panelOpen;
  };

  toggleMini = () => {
    this.miniOpen = !this.miniOpen;
    this.miniPref = this.miniOpen;
    if (this.engine) {
      this.engine.showMini = this.miniOpen;
    }
  };

  onTurn = (e: Event) => {
    this.turnPos = Number((e.target as HTMLInputElement).value);
    if (this.engine) {
      this.engine.baseSpin = (this.turnPos / 100) * 0.01;
    }
  };

  /* the atlas isn't a separate view — sliceMode alone decides whether the
     page is open (>0) and which cut it shows, so scan segment, the single
     cycling button, and the drag/scrub all just set this one number */
  setSlice = (mode: number) => {
    let changed = mode !== this.sliceMode;
    this.sliceMode = mode;
    this.layerKey = -1;
    if (this.engine) {
      this.engine.sliceTarget = mode;
      this.engine.chartTarget = mode > 0 ? 1 : 0;
    }
    this.applyScan();
    // announce every view change — Munsell's axes aren't obvious, and
    // neither is the scrub gesture (hue pages turn ⟷, value cuts move ↕)
    if (changed && mode === 1) {
      this.showToast('HUE · a vertical leaf — drag ⟷ to turn the pages', 3000);
    } else if (changed && mode === 2) {
      this.showToast(
        'VALUE · a horizontal cut — drag ↕ to move through lightness',
        3000,
      );
    } else if (changed && mode === 0) {
      this.showToast('atlas closed · the whole solid, drag to tumble', 3000);
    }
  };

  get scanLabel(): string {
    return (
      ['OPEN THE ATLAS', 'SLICE BY VALUE', 'CLOSE THE ATLAS'][this.sliceMode] ??
      'OPEN THE ATLAS'
    );
  }

  cycleScan = () => {
    this.setSlice((this.sliceMode + 1) % 3);
  };

  /* the same morph dial does double duty: tree ↔ sphere when the atlas
     is closed, Munsell's measured chroma ↔ the ideal linear grid when
     it's open — one continuous knob instead of a second toggle */
  get morphLabel(): string {
    if (this.sliceMode !== 0) {
      return this.morphed ? 'MUNSELL SCALE' : 'LINEAR SCALE';
    }
    return this.morphed ? 'TO MUNSELL' : 'TO ITTEN';
  }

  toggleMorph = () => {
    this.morphed = !this.morphed;
    if (this.engine) {
      this.engine.morphTarget = this.morphed ? 1 : 0;
    }
    this.playGliss(this.morphed);
    this.morphState = this.morphed ? 'dreaming…' : 'waking…';
    clearTimeout(this.morphTimer);
    this.morphTimer = window.setTimeout(() => {
      this.morphState = this.morphed ? 'sphere dreamt' : 'tree measured';
    }, 1400);
  };

  toggleGyro = async () => {
    if (this.gyroOn) {
      this.gyroOn = false;
      window.removeEventListener('deviceorientation', this.onGyro);
      return;
    }
    try {
      let doe = DeviceOrientationEvent as unknown as {
        requestPermission?: () => Promise<string>;
      };
      if (typeof doe.requestPermission === 'function') {
        let res = await doe.requestPermission();
        if (res !== 'granted') {
          this.showToast('gyro permission declined');
          return;
        }
      }
      this.gLast = null;
      window.addEventListener('deviceorientation', this.onGyro);
      this.gyroOn = true;
    } catch {
      this.showToast('gyro unavailable');
    }
  };

  onGyro = (e: DeviceOrientationEvent) => {
    if (e.alpha == null || e.beta == null || !this.engine) {
      return;
    }
    if (this.gLast) {
      this.engine.tumble(
        (e.alpha - this.gLast.a) * 2.2,
        (e.beta - this.gLast.b) * 2.2,
      );
    }
    this.gLast = { a: e.alpha, b: e.beta };
  };

  togglePause = () => {
    this.paused = !this.paused;
    if (this.engine) {
      this.engine.paused = this.paused;
    }
  };

  /* the scan flicks layer by layer, like turning pages — never a smear */
  snapScan(): { snapped: number; key: number } {
    let p = this.slicePos / 100;
    if (this.sliceMode === 2) {
      let v = 1 + Math.min(8, Math.floor(p * 9));
      return { snapped: v / 10, key: 1000 + v };
    }
    let leaves = HUE_TIERS[this.densityIdx] / 2;
    let j = Math.floor((((p % 1) + 1) % 1) * leaves) % leaves;
    return { snapped: (j * 2) / HUE_TIERS[this.densityIdx], key: j };
  }

  /* one gesture, one truth: slider moves and page-scrubs both land here.
     There's no separate atlas state to sync — sliceTarget/uSlicePos on the
     engine ARE what decides both the 3D cut and the flattened page */
  applyScan() {
    let { snapped, key } = this.snapScan();
    if (this.engine) {
      this.engine.uniforms.uSlicePos.value = snapped;
      this.engine.buildGrid(this.sliceMode, snapped);
    }
    let layerChanged = key !== this.layerKey;
    this.layerKey = key;
    if (layerChanged) {
      this.updateSliceSound();
    }
  }

  onSlicePos = (e: Event) => {
    this.slicePos = Number((e.target as HTMLInputElement).value);
    this.applyScan();
  };

  onChroma = (e: Event) => {
    this.chromaPos = Number((e.target as HTMLInputElement).value);
    if (this.engine) {
      this.engine.uniforms.uChroma.value = this.chromaPos / 100;
    }
  };

  onGlow = (e: Event) => {
    this.glowPos = Number((e.target as HTMLInputElement).value);
    if (this.engine) {
      this.engine.uniforms.uGlow.value = this.glowPos / 100;
    }
  };

  onContrast = (e: Event) => {
    this.contrastPos = Number((e.target as HTMLInputElement).value);
    if (this.engine) {
      this.engine.uniforms.uContrast.value = this.contrastPos / 100;
    }
    // contrast detunes the pad's middle voice so complements beat, gently
    if (this.audioCtx && this.padOsc2) {
      this.padOsc2.detune.setTargetAtTime(
        (this.contrastPos / 100) * 9,
        this.audioCtx.currentTime,
        0.3,
      );
    }
  };

  /* what the panel reports: the page's cut when it's open, otherwise the
     state of the 3D solid */
  get statsCaption(): string {
    let scanOpen = this.sliceMode !== 0;
    let state = scanOpen
      ? this.morphed
        ? 'linear field · every step'
        : "munsell scale · the eye's selection"
      : this.morphState;
    let cut = '';
    if (scanOpen && this.sliceMode === 1) {
      let h = this.snapScan().snapped / 2;
      cut = ` · vertical leaf ${hueLabel(h)} / ${hueLabel((h + 0.5) % 1)}`;
    } else if (scanOpen && this.sliceMode === 2) {
      cut = ` · horizontal cut at value ${this.snapScan().key - 1000}`;
    }
    return `${state}${cut}`;
  }

  get atlasIsOpen() {
    return this.sliceMode !== 0;
  }

  /* the density and slice rows are the same "chip toggle group" shape
     three times over — one data array per row instead of hand-repeating
     the Button markup per option */
  densityOptions = [
    { value: 0, label: '10' },
    { value: 1, label: '20' },
    { value: 2, label: '40' },
  ];

  sliceOptions = [
    { value: 0, label: 'OFF' },
    {
      value: 1,
      label: 'HUE',
      title: 'vertical leaf through the trunk — drag ⟷ to turn the pages',
    },
    {
      value: 2,
      label: 'VALUE',
      title: 'horizontal cut across the trunk — drag ↕ to move through values',
    },
  ];

  /* the hint speaks to the view that's actually on stage: gestures for
     the 3D solid, page-reading for the open atlas */
  get hintText(): string {
    if (this.sliceMode === 1) {
      return 'drag ⟷ to turn the hue pages · hold a spot on the open page to copy its hex';
    }
    if (this.sliceMode === 2) {
      return 'drag ↕ to move through the value cuts · hold a spot on the open page to copy its hex';
    }
    return 'drag to tumble · scroll to approach · double-click to refit';
  }

  get selectedHex() {
    return this.args.color ?? '';
  }

  get selectedNotation() {
    return this.args.munsell ?? '';
  }

  <template>
    {{! template-lint-disable no-pointer-down-event-binding }}
    <div class={{cn 'room' compact=@compact}}>
      <canvas
        class='stage'
        role='img'
        aria-label='3D Munsell color solid — drag to rotate, scroll to zoom'
        {{this.setupScene}}
        {{on 'pointerdown' this.onPointerDown}}
        {{on 'pointermove' this.onPointerMove}}
        {{on 'pointerup' this.onPointerUp}}
        {{on 'wheel' this.onWheel}}
        {{on 'dblclick' this.onDblClick}}
      ></canvas>

      <header class='masthead'>
        <div class='kanji' aria-hidden='true'>色 立 体</div>
        {{! h2, not h1 — this studio is an edit format nested in a host
            surface that owns the page's h1 }}
        <h2 class='name'>THE COLOR TREE</h2>
        <p class='credit'>after Munsell × Itten</p>
      </header>

      <button
        type='button'
        class={{cn 'hamburger' panel-open=this.panelOpen}}
        data-test-toggle-panel
        aria-label='Toggle control panel'
        aria-pressed='{{this.panelOpen}}'
        {{on 'click' this.togglePanel}}
      >{{if this.panelOpen '✕' '☰'}}</button>

      {{! the live region is always in the DOM so a screen reader is already
          watching it when the text arrives; announcing only works if the
          region pre-exists the content change }}
      <div class='toast-live' role='status'>
        {{#if this.toast}}
          <button
            type='button'
            class='toast'
            title='dismiss'
            data-test-toast
            {{on 'click' this.dismissToast}}
          >{{this.toast}}<span
              class='toast-x'
              aria-hidden='true'
            >✕</span></button>
        {{/if}}
      </div>

      {{#if this.atlasIsOpen}}
        {{#if this.miniOpen}}
          <div class='mini-frame'></div>
        {{/if}}
        <IconButton
          @icon={{if this.miniOpen EyeOffIcon EyeIcon}}
          @width='0.95rem'
          @height='0.95rem'
          class={{cn 'mini-toggle' mini-open=this.miniOpen}}
          data-test-toggle-mini
          aria-pressed='{{this.miniOpen}}'
          aria-label='Toggle 3D preview'
          title={{if this.miniOpen 'Hide 3D preview' 'Show 3D preview'}}
          {{on 'click' this.toggleMini}}
        />
      {{/if}}

      {{#each this.pickFxList key='id' as |fx|}}
        <div
          class='pick-fx'
          style={{cssVar fx-x=fx.cssX fx-y=fx.cssY fx-color=fx.hex}}
        ></div>
      {{/each}}

      <div class='stage-actions'>
        <Button
          @kind='text-only'
          class='chip wide'
          {{on 'click' this.toggleMorph}}
        >
          {{this.morphLabel}}
        </Button>
        <Button
          @kind='text-only'
          class='chip wide'
          data-test-scan
          {{on 'click' this.cycleScan}}
        >
          {{this.scanLabel}}
        </Button>
      </div>
      <p class='hint'>{{this.hintText}}</p>

      {{#if this.panelOpen}}
        <aside class='panel'>
          <div class='prow'>
            <span class='label' id='{{this.uid}}-density'>hue pages</span>
            <span
              class='pgroup'
              role='group'
              aria-labelledby='{{this.uid}}-density'
            >
              {{#each this.densityOptions as |opt|}}
                <Button
                  @kind='text-only'
                  class={{cn 'chip sq' active=(eq this.densityIdx opt.value)}}
                  aria-pressed='{{eq this.densityIdx opt.value}}'
                  {{on 'click' (fn this.setDensity opt.value)}}
                >{{opt.label}}</Button>
              {{/each}}
            </span>
          </div>
          <div class='prow'>
            <span class='label' id='{{this.uid}}-slice'>slice</span>
            <span
              class='pgroup'
              role='group'
              aria-labelledby='{{this.uid}}-slice'
            >
              {{#each this.sliceOptions as |opt|}}
                <Button
                  @kind='text-only'
                  class={{cn 'chip sq' active=(eq this.sliceMode opt.value)}}
                  aria-pressed='{{eq this.sliceMode opt.value}}'
                  title={{opt.title}}
                  {{on 'click' (fn this.setSlice opt.value)}}
                >{{opt.label}}</Button>
              {{/each}}
            </span>
          </div>
          {{#if (eq this.sliceMode 1)}}
            <p class='slice-note'>vertical leaf, one hue pair — drag ⟷ to turn
              the pages</p>
          {{/if}}
          {{#if (eq this.sliceMode 2)}}
            <p class='slice-note'>horizontal cut, one lightness — drag ↕ to move
              through values</p>
          {{/if}}
          <div class='prow'>
            <label class='label' for='{{this.uid}}-scan'>scan</label>
            <input
              id='{{this.uid}}-scan'
              type='range'
              class='dial'
              min='0'
              max='100'
              value={{this.slicePos}}
              disabled={{eq this.sliceMode 0}}
              title={{if
                (eq this.sliceMode 0)
                'open a slice or the atlas first'
                'turn the pages of the open cut'
              }}
              {{on 'input' this.onSlicePos}}
            />
          </div>
          <div class='prow'>
            <label class='label' for='{{this.uid}}-chroma'>chroma</label>
            <input
              id='{{this.uid}}-chroma'
              type='range'
              class='dial'
              min='0'
              max='100'
              value={{this.chromaPos}}
              {{on 'input' this.onChroma}}
            />
          </div>
          <div class='prow'>
            <label class='label' for='{{this.uid}}-glow'>glow</label>
            <input
              id='{{this.uid}}-glow'
              type='range'
              class='dial'
              min='0'
              max='100'
              value={{this.glowPos}}
              {{on 'input' this.onGlow}}
            />
          </div>
          <div class='prow'>
            <label class='label' for='{{this.uid}}-contrast'>contrast</label>
            <input
              id='{{this.uid}}-contrast'
              type='range'
              class='dial'
              min='0'
              max='100'
              value={{this.contrastPos}}
              {{on 'input' this.onContrast}}
            />
          </div>
          <div class='prow'>
            <label class='label' for='{{this.uid}}-turn'>turn</label>
            <input
              id='{{this.uid}}-turn'
              type='range'
              class='dial'
              min='0'
              max='100'
              value={{this.turnPos}}
              {{on 'input' this.onTurn}}
            />
          </div>
          <div class='prow'>
            <Button
              @kind='text-only'
              class='chip'
              aria-pressed='{{this.paused}}'
              {{on 'click' this.togglePause}}
            >
              {{if this.paused 'RESUME' 'PAUSE'}}
            </Button>
            <Button
              @kind='text-only'
              class='chip'
              aria-pressed='{{this.soundOn}}'
              {{on 'click' this.toggleSound}}
            >
              {{if this.soundOn 'SOUND OFF' 'SOUND ON'}}
            </Button>
            {{#if this.gyroAvailable}}
              <Button
                @kind='text-only'
                class={{cn 'chip' active=this.gyroOn}}
                {{on 'click' this.toggleGyro}}
              >GYRO</Button>
            {{/if}}
          </div>
          <p class='stats'>{{this.chipCount}} voxels · {{this.statsCaption}}</p>
          {{#if this.selectedHex}}
            <Swatch
              class='picked'
              @style='round'
              @color={{this.selectedHex}}
              @label={{this.selectedNotation}}
            />
          {{/if}}
          <p class='note'>Munsell measured color and it would not stay a sphere:
            every hue climbs to its own peak chroma at its own value, so the
            solid grows into a lopsided tree. Itten believed in the sphere
            anyway — morph between the two, slice the solid open, or read it
            page by page in the atlas.</p>
        </aside>
      {{/if}}
    </div>

    <style scoped>
      /* The room is an intrinsically dark object, not a themed surface: a
         Munsell solid reads wrongly against a light ground, so the stage must
         stay dark under every theme. That is what the --tooltip pair is for
         (pret-ui token table, "any intrinsically dark object"). Both the ground
         and its ink come from that one pair so they can never disagree, and a
         theme can still restyle it — unlike a stamped data-theme, which would
         override a linked theme's own values. */
      .room {
        --panel-w: min(21rem, 85%);
        position: relative;
        width: 100%;
        height: 100vh;
        max-height: 100%;
        overflow: hidden;
        /* atmospheric vignette, not a colour choice: white/black are the
           lighten/darken DIRECTION applied to the theme's own --tooltip, so
           the gradient tracks the theme rather than pinning a literal. srgb
           is deliberate here — oklch flattens the falloff. Not a rule-6 hit. */
        background: radial-gradient(
          120% 90% at 50% 30%,
          color-mix(in srgb, var(--tooltip) 92%, white) 0%,
          var(--tooltip) 55%,
          color-mix(in srgb, var(--tooltip) 82%, black) 100%
        );
        color: var(--tooltip-foreground);
        font-family: var(--font-mono);
      }
      /* field edit format: a bounded studio instead of a full-height room */
      .room.compact {
        height: 100%;
        min-height: 26rem;
      }
      .room.compact .masthead .name {
        font-size: 1rem;
      }
      .room.compact .kanji {
        display: none;
      }
      /* in the bounded studio the open panel's docked ✕ would collide with
         the masthead — the panel takes the stage, the nameplate yields */
      .room.compact:has(.hamburger.panel-open) .masthead {
        opacity: 0;
      }
      .stage {
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
        display: block;
        touch-action: none;
        cursor: grab;
      }
      .stage:active {
        cursor: grabbing;
      }
      .masthead {
        position: absolute;
        top: 1.6rem;
        left: 1.8rem;
        pointer-events: none;
      }
      .kanji {
        letter-spacing: 0.6em;
        font-size: 0.8rem;
        opacity: 0.55;
      }
      .name {
        margin: 0.4rem 0 0;
        font-size: 1.5rem;
        letter-spacing: 0.42em;
        font-weight: 500;
      }
      .credit {
        margin: 0.3rem 0 0;
        font-size: 0.62rem;
        letter-spacing: 0.22em;
        opacity: 0.5;
      }
      .hint {
        position: absolute;
        bottom: 1rem;
        left: 50%;
        transform: translateX(-50%);
        margin: 0;
        font-size: 0.6rem;
        letter-spacing: 0.14em;
        opacity: 0.38;
        pointer-events: none;
        white-space: nowrap;
      }
      .hamburger {
        position: absolute;
        top: 1.2rem;
        right: 1.2rem;
        z-index: 30;
        transition: right 0.25s ease;
        width: 2.3rem;
        height: 2.3rem;
        border: 1px solid
          color-mix(in oklch, var(--tooltip-foreground) 22%, transparent);
        border-radius: 50%;
        background-color: color-mix(in oklch, var(--tooltip) 55%, transparent);
        color: var(--tooltip-foreground);
        font-size: 0.95rem;
        cursor: pointer;
      }
      /* while the panel is open the button reads as its handle, sitting
         just outside the panel's left edge */
      .hamburger.panel-open {
        right: calc(var(--panel-w) + 0.9rem);
      }
      /* Swatch renders [label][value][preview]; the studio's chip reads
         [preview][hex][notation], so the preview is pulled first with
         `order` rather than re-typing the component. */
      .picked {
        gap: 0.55rem;
        margin-top: 0.9rem;
        padding: 0.45rem 0.7rem;
        border: 1px solid
          color-mix(in oklch, var(--tooltip-foreground) 18%, transparent);
        border-radius: 999px;
        background-color: color-mix(in oklch, var(--tooltip) 55%, transparent);
        font-size: 0.68rem;
        letter-spacing: 0.08em;
        --boxel-swatch-border-color: color-mix(
          in oklch,
          var(--tooltip-foreground) 35%,
          transparent
        );
      }
      .picked :deep(.boxel-swatch-preview) {
        order: -1;
        width: 1rem;
        height: 1rem;
        border-radius: 50%;
        flex-shrink: 0;
      }
      .picked :deep(.boxel-swatch-label) {
        display: flex;
        flex-direction: row-reverse;
        align-items: center;
        gap: 0.55rem;
      }
      .picked :deep(.boxel-swatch-name) {
        opacity: 0.6;
      }
      .picked :deep(.boxel-swatch-value) {
        font: inherit;
      }
      .pick-fx {
        position: absolute;
        left: var(--fx-x);
        top: var(--fx-y);
        width: 1rem;
        height: 1rem;
        /* half the dot, to centre it on the click point JS sets via left/top */
        margin: -0.5rem 0 0 -0.5rem;
        border-radius: 50%;
        background-color: var(--fx-color);
        box-shadow:
          0 0 18px 4px var(--fx-color),
          0 0 42px 14px color-mix(in oklch, var(--fx-color) 55%, transparent);
        pointer-events: none;
        z-index: 25;
        animation: pick-pulse 0.75s ease-out forwards;
      }
      @keyframes pick-pulse {
        0% {
          opacity: 0.95;
          scale: 0.5;
        }
        60% {
          opacity: 0.6;
          scale: 2.1;
        }
        100% {
          opacity: 0;
          scale: 2.8;
        }
      }
      .mini-frame {
        /* frames the scout miniature, which is scissor-rendered into the
           same canvas at these exact coordinates (bottom-left origin).
           px is deliberate and rule-3 exempt: these mirror tree-engine's
           setScissor(14, 110, miniSize, miniSize) and
           miniSize = min(w * 0.32, 168), which are WebGL pixel space. In rem
           they would desync from the render at any root font-size but 16px. */
        position: absolute;
        left: 14px;
        bottom: 110px;
        width: min(32%, 168px);
        aspect-ratio: 1;
        border: 1px solid
          color-mix(in oklch, var(--tooltip-foreground) 22%, transparent);
        pointer-events: none;
        z-index: 5;
      }
      /* re-skinned via IconButton's own custom-property knobs (boxel-ui's
         re-skin rule) rather than raw width/height/background/color, which
         a bare .mini-toggle selector could lose to .boxel-icon-button's own
         rule depending on stylesheet load order; the compound selector
         (both classes live on the same element) wins on specificity either
         way, which border/border-radius still need since IconButton hands
         those no knob at all */
      .mini-toggle.boxel-icon-button {
        /* docked inside the scout frame's bottom-left corner (the frame
           anchors at 14px/110px), so the scout can be waved away when it
           covers the atlas page — and invited back from the same spot.
           px for the same rule-3 exemption as .mini-frame: this offset is
           measured against that canvas-pixel anchor, not the type scale */
        position: absolute;
        left: 20px;
        bottom: 116px;
        --boxel-icon-button-width: 1.6rem;
        --boxel-icon-button-height: 1.6rem;
        --boxel-icon-button-background: color-mix(
          in oklch,
          var(--tooltip) 45%,
          transparent
        );
        --boxel-icon-button-color: var(--tooltip-foreground);
        border: 1px solid
          color-mix(in oklch, var(--tooltip-foreground) 22%, transparent);
        border-radius: 0.125rem;
        z-index: 6;
        transition:
          background 0.2s ease,
          color 0.2s ease;
      }
      .mini-toggle.boxel-icon-button:hover {
        --boxel-icon-button-background: color-mix(
          in oklch,
          var(--tooltip-foreground) 12%,
          transparent
        );
      }
      .mini-toggle.boxel-icon-button.mini-open {
        --boxel-icon-button-color: var(--primary);
      }
      /* the wrapper carries the placement so the always-present live region
         adds no layout or hit area of its own when empty */
      .toast-live {
        position: absolute;
        bottom: 7.5rem;
        left: 50%;
        transform: translateX(-50%);
        z-index: 40;
        pointer-events: none;
      }
      .toast {
        pointer-events: auto;
        padding: 0.5rem 0.9rem;
        border-radius: 999px;
        background-color: color-mix(in oklch, var(--primary) 92%, transparent);
        color: var(--primary-foreground);
        font: inherit;
        font-size: 0.68rem;
        letter-spacing: 0.08em;
        text-align: center;
        border: none;
        cursor: pointer;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 0.5rem;
        animation: toast-glow 1.8s ease-out;
      }
      .toast-x {
        opacity: 0.55;
        font-size: 0.6rem;
      }
      .toast:hover .toast-x {
        opacity: 1;
      }
      @keyframes toast-glow {
        0% {
          box-shadow: 0 0 0 0
            color-mix(in oklch, var(--primary) 70%, transparent);
        }
        45% {
          box-shadow: 0 0 22px 4px
            color-mix(in oklch, var(--primary) 45%, transparent);
        }
        100% {
          box-shadow: 0 0 0 0 transparent;
        }
      }
      .stage-actions {
        position: absolute;
        bottom: 2.4rem;
        left: 50%;
        transform: translateX(-50%);
        display: flex;
        gap: 0.8rem;
      }
      .chip {
        padding: 0.38rem 0.8rem;
        border: 1px solid
          color-mix(in oklch, var(--tooltip-foreground) 22%, transparent);
        border-radius: 0.125rem;
        background-color: color-mix(in oklch, var(--tooltip) 45%, transparent);
        color: var(--tooltip-foreground);
        font: inherit;
        font-size: 0.62rem;
        letter-spacing: 0.14em;
        cursor: pointer;
        transition:
          background 0.2s ease,
          color 0.2s ease;
      }
      .chip:hover {
        background-color: color-mix(
          in oklch,
          var(--tooltip-foreground) 12%,
          transparent
        );
      }
      .chip.active {
        background-color: var(--primary);
        color: var(--primary-foreground);
      }
      .chip.wide {
        min-width: 8rem;
      }
      .chip.sq {
        padding: 0.3rem 0.5rem;
      }
      .dial {
        width: 8.2rem;
        accent-color: var(--primary);
      }
      .dial:disabled {
        opacity: 0.3;
        cursor: default;
      }
      .slice-note {
        margin: -0.15rem 0 0;
        padding: 0.2rem 0.4rem;
        border-radius: 0.125rem;
        font-size: 0.6rem;
        letter-spacing: 0.08em;
        /* --muted-foreground may only sit on --muted/--background/--card, so
           on this dark ground the de-emphasis is a dilution of the room's ink */
        color: color-mix(in oklch, var(--tooltip-foreground) 70%, transparent);
        animation: slice-note-pulse 2.2s ease-out;
      }
      @keyframes slice-note-pulse {
        0%,
        45% {
          color: var(--primary-foreground);
          background-color: color-mix(
            in oklch,
            var(--primary) 85%,
            transparent
          );
        }
        100% {
          color: color-mix(
            in oklch,
            var(--tooltip-foreground) 70%,
            transparent
          );
          background-color: transparent;
        }
      }
      .panel {
        position: absolute;
        top: 0;
        right: 0;
        bottom: 0;
        z-index: 20;
        width: var(--panel-w);
        padding: 1.4rem;
        border-left: 1px solid
          color-mix(in oklch, var(--tooltip-foreground) 14%, transparent);
        background-color: color-mix(in oklch, var(--tooltip) 86%, transparent);
        backdrop-filter: blur(8px);
        overflow-y: auto;
        box-sizing: border-box;
      }
      .prow {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 0.6rem;
        margin-bottom: 0.85rem;
      }
      .pgroup {
        display: flex;
        gap: 0.3rem;
      }
      .label {
        font-size: 0.58rem;
        letter-spacing: 0.2em;
        text-transform: uppercase;
        opacity: 0.45;
      }
      .stats {
        margin: 1.2rem 0 0;
        font-size: 0.6rem;
        letter-spacing: 0.12em;
        opacity: 0.5;
        line-height: 1.6;
      }
      .note {
        margin: 1.2rem 0 0;
        font-size: 0.66rem;
        line-height: 1.75;
        opacity: 0.65;
      }
    </style>
  </template>
}
