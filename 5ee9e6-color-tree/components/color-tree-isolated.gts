// =============================================================================
// IsolatedColorTree — the room the specimen is held in. The isolated format
// IS the app: tumble the solid, slice it open (HUE leaf / VALUE plane),
// open the atlas (the same voxels laid flat as a page), morph between
// Munsell's measured tree and Itten's idealized sphere, and pick colors
// straight off the canvas. All WebGL work lives in utils/tree-engine.
// =============================================================================
import { Component } from 'https://cardstack.com/base/card-api';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { modifier } from 'ember-modifier';
import { htmlSafe } from '@ember/template';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Button } from '@cardstack/boxel-ui/components';
import { debounce } from 'lodash';
import { HUE_TIERS, hueLabel, swatchStyle } from '../utils/munsell';
import { TreeEngine } from '../utils/tree-engine';
import type { ColorTree } from '../color-tree';

/* ═══════════════════════════════════════════════════════════════════════════
   ISOLATED — the room the specimen is held in
   ═══════════════════════════════════════════════════════════════════════════ */
export class IsolatedColorTree extends Component<typeof ColorTree> {
  @tracked densityIdx = 1;
  @tracked sliceMode = 0; // 0 off · 1 hue · 2 value
  @tracked morphed = false; // false = Munsell tree · true = Itten sphere
  @tracked paused = false;
  @tracked slicePos = 50;
  @tracked chromaPos = 100;
  @tracked glowPos = 50;
  @tracked contrastPos = 0;
  @tracked toast = '';
  @tracked panelOpen = true;
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
  lastToneAt = 0;
  morphTimer = 0;
  ptrs = new Map<number, { x: number; y: number }>();
  lastPinch: number | null = null;
  holdTimer = 0;
  holdFired = false;
  layerKey = -1;
  gLast: { a: number; b: number } | null = null;
  engine?: TreeEngine;

  /* rapid picking shouldn't hammer the card with saves — the last
     selection within 300ms is the one that's kept */
  saveSelection = debounce((hex: string, notation: string) => {
    this.args.model.selectedColor = hex;
    this.args.model.selectedMunsell = notation;
  }, 300);

  toggleSound = () => {
    this.soundOn = !this.soundOn;
    if (this.soundOn && !this.audioCtx) {
      try {
        this.audioCtx = new AudioContext();
      } catch {
        this.soundOn = false;
      }
    }
    this.audioCtx?.resume?.();
  };

  /* a small sine voice: the atlas hums when scrubbed, chimes when copied */
  playTone(freq: number, dur = 0.09, gain = 0.05) {
    if (!this.soundOn || !this.audioCtx) {
      return;
    }
    let ctx = this.audioCtx;
    let osc = ctx.createOscillator();
    let g = ctx.createGain();
    osc.type = 'sine';
    osc.frequency.value = freq;
    g.gain.setValueAtTime(gain, ctx.currentTime);
    g.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + dur);
    osc.connect(g).connect(ctx.destination);
    osc.start();
    osc.stop(ctx.currentTime + dur);
  }

  scrubTone(pos: number) {
    let now = performance.now();
    if (now - this.lastToneAt < 60) {
      return;
    }
    this.lastToneAt = now;
    this.playTone(220 + pos * 6.6);
  }

  copyChime() {
    // two quick sine notes a fifth apart — a glass tap
    this.playTone(1318.51, 0.1, 0.06);
    setTimeout(() => this.playTone(1975.53, 0.14, 0.05), 90);
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
      this.audioCtx?.close?.();
      this.audioCtx = undefined;
      ro.disconnect();
      engine.dispose();
      this.engine = undefined;
    };
  });

  showToast = (msg: string) => {
    this.toast = msg;
    clearTimeout(this.toastTimer);
    this.toastTimer = window.setTimeout(() => (this.toast = ''), 1800);
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

  get pickFxList() {
    return this.pickFx ? [this.pickFx] : [];
  }

  /* hex comes from our own chipHex/rgbHex, so it's always a #rrggbb
     literal — never an unvalidated string interpolated into a style */
  pickFxStyle = (fx: { x: number; y: number; hex: string }) =>
    htmlSafe(`left: ${fx.x}px; top: ${fx.y}px; --fx-color: ${fx.hex}`);

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
  };

  togglePanel = () => {
    this.panelOpen = !this.panelOpen;
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
    this.sliceMode = mode;
    this.layerKey = -1;
    if (this.engine) {
      this.engine.sliceTarget = mode;
      this.engine.chartTarget = mode > 0 ? 1 : 0;
    }
    this.applyScan();
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
    if (layerChanged && this.sliceMode !== 0) {
      this.scrubTone(this.slicePos);
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
      cut = ` · leaf ${hueLabel(h)} / ${hueLabel((h + 0.5) % 1)}`;
    } else if (scanOpen && this.sliceMode === 2) {
      cut = ` · value ${this.snapScan().key - 1000} cut`;
    }
    return `${state}${cut}`;
  }

  get atlasIsOpen() {
    return this.sliceMode !== 0;
  }

  get hasLinkedTheme() {
    return Boolean((this.args.model as any)?.cardInfo?.theme);
  }

  get selectedHex() {
    return this.args.model.selectedColor ?? '';
  }

  get selectedNotation() {
    return this.args.model.selectedMunsell ?? '';
  }

  <template>
    {{! template-lint-disable no-pointer-down-event-binding }}
    <div class='room {{unless this.hasLinkedTheme "ct-default-theme"}}'>
      <canvas
        class='stage'
        {{this.setupScene}}
        {{on 'pointerdown' this.onPointerDown}}
        {{on 'pointermove' this.onPointerMove}}
        {{on 'pointerup' this.onPointerUp}}
        {{on 'wheel' this.onWheel}}
        {{on 'dblclick' this.onDblClick}}
      ></canvas>

      <header class='masthead'>
        <div class='kanji'>色 立 体</div>
        <h1 class='name'>THE COLOR TREE</h1>
        <p class='credit'>after Munsell × Itten</p>
      </header>

      <button
        type='button'
        class='hamburger'
        aria-label='Toggle control panel'
        {{on 'click' this.togglePanel}}
      >☰</button>

      {{#if this.toast}}
        <div class='toast'>{{this.toast}}</div>
      {{/if}}

      {{#if this.atlasIsOpen}}
        <div class='mini-frame'></div>
      {{/if}}

      {{#each this.pickFxList key='id' as |fx|}}
        <div class='pick-fx' style={{this.pickFxStyle fx}}></div>
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
          {{on 'click' this.cycleScan}}
        >
          {{this.scanLabel}}
        </Button>
      </div>
      <p class='hint'>drag to tumble · scroll to approach · double-click to
        refit · swipe the atlas layer by layer · hold a spot on the open page to
        copy its hex</p>

      {{#if this.panelOpen}}
        <aside class='panel'>
          <div class='prow'>
            <span class='label'>hue pages</span>
            <span class='pgroup'>
              <Button
                @kind='text-only'
                class='chip sq {{if (eq this.densityIdx 0) "active"}}'
                {{on 'click' (fn this.setDensity 0)}}
              >10</Button>
              <Button
                @kind='text-only'
                class='chip sq {{if (eq this.densityIdx 1) "active"}}'
                {{on 'click' (fn this.setDensity 1)}}
              >20</Button>
              <Button
                @kind='text-only'
                class='chip sq {{if (eq this.densityIdx 2) "active"}}'
                {{on 'click' (fn this.setDensity 2)}}
              >40</Button>
            </span>
          </div>
          <div class='prow'>
            <span class='label'>slice</span>
            <span class='pgroup'>
              <Button
                @kind='text-only'
                class='chip sq {{if (eq this.sliceMode 0) "active"}}'
                {{on 'click' (fn this.setSlice 0)}}
              >OFF</Button>
              <Button
                @kind='text-only'
                class='chip sq {{if (eq this.sliceMode 1) "active"}}'
                {{on 'click' (fn this.setSlice 1)}}
              >HUE</Button>
              <Button
                @kind='text-only'
                class='chip sq {{if (eq this.sliceMode 2) "active"}}'
                {{on 'click' (fn this.setSlice 2)}}
              >VALUE</Button>
            </span>
          </div>
          <div class='prow'>
            <span class='label'>scan</span>
            <input
              type='range'
              class='dial'
              min='0'
              max='100'
              value={{this.slicePos}}
              aria-label='scan'
              {{on 'input' this.onSlicePos}}
            />
          </div>
          <div class='prow'>
            <span class='label'>chroma</span>
            <input
              type='range'
              class='dial'
              min='0'
              max='100'
              value={{this.chromaPos}}
              aria-label='chroma'
              {{on 'input' this.onChroma}}
            />
          </div>
          <div class='prow'>
            <span class='label'>glow</span>
            <input
              type='range'
              class='dial'
              min='0'
              max='100'
              value={{this.glowPos}}
              aria-label='glow'
              {{on 'input' this.onGlow}}
            />
          </div>
          <div class='prow'>
            <span class='label'>contrast</span>
            <input
              type='range'
              class='dial'
              min='0'
              max='100'
              value={{this.contrastPos}}
              aria-label='contrast'
              {{on 'input' this.onContrast}}
            />
          </div>
          <div class='prow'>
            <span class='label'>turn</span>
            <input
              type='range'
              class='dial'
              min='0'
              max='100'
              value={{this.turnPos}}
              aria-label='turn'
              {{on 'input' this.onTurn}}
            />
          </div>
          <div class='prow'>
            <Button
              @kind='text-only'
              class='chip'
              {{on 'click' this.togglePause}}
            >
              {{if this.paused 'RESUME' 'PAUSE'}}
            </Button>
            <Button
              @kind='text-only'
              class='chip'
              {{on 'click' this.toggleSound}}
            >
              {{if this.soundOn 'SOUND ON' 'SOUND OFF'}}
            </Button>
            {{#if this.gyroAvailable}}
              <Button
                @kind='text-only'
                class='chip {{if this.gyroOn "active"}}'
                {{on 'click' this.toggleGyro}}
              >GYRO</Button>
            {{/if}}
          </div>
          <p class='stats'>{{this.chipCount}} voxels · {{this.statsCaption}}</p>
          {{#if this.selectedHex}}
            <div class='picked'>
              <span
                class='picked-swatch'
                style={{swatchStyle this.selectedHex}}
              ></span>
              <span class='picked-hex'>{{this.selectedHex}}</span>
              <span class='picked-munsell'>{{this.selectedNotation}}</span>
            </div>
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
      .room {
        position: relative;
        width: 100%;
        height: 100vh;
        max-height: 100%;
        overflow: hidden;
        background: radial-gradient(
          120% 90% at 50% 30%,
          color-mix(in srgb, var(--background, #050a12) 92%, white) 0%,
          var(--background, #050a12) 55%,
          color-mix(in srgb, var(--background, #050a12) 82%, black) 100%
        );
        color: var(--foreground, #e8f1f4);
        font-family: var(
          --font-mono,
          ui-monospace,
          'SF Mono',
          Menlo,
          monospace
        );
      }
      .ct-default-theme {
        --background: #050a12;
        --foreground: #e8f1f4;
        --border: #e8f1f4;
        --primary: #e8f1f4;
        --primary-foreground: #0a1522;
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
        width: 2.3rem;
        height: 2.3rem;
        border: 1px solid
          color-mix(in srgb, var(--border, #e8f1f4) 22%, transparent);
        border-radius: 50%;
        background: color-mix(
          in srgb,
          var(--background, #03070e) 55%,
          transparent
        );
        color: var(--foreground, #e8f1f4);
        font-size: 0.95rem;
        cursor: pointer;
      }
      .picked {
        display: flex;
        align-items: center;
        gap: 0.55rem;
        margin-top: 0.9rem;
        padding: 0.45rem 0.7rem;
        border: 1px solid
          color-mix(in srgb, var(--border, #e8f1f4) 18%, transparent);
        border-radius: 999px;
        background: color-mix(
          in srgb,
          var(--background, #03070e) 55%,
          transparent
        );
        font-size: 0.68rem;
        letter-spacing: 0.08em;
      }
      .picked-swatch {
        width: 1rem;
        height: 1rem;
        border-radius: 50%;
        border: 1px solid rgba(255, 255, 255, 0.35);
        flex-shrink: 0;
      }
      .picked-munsell {
        opacity: 0.6;
      }
      .pick-fx {
        position: absolute;
        width: 16px;
        height: 16px;
        margin: -8px 0 0 -8px;
        border-radius: 50%;
        background: var(--fx-color);
        box-shadow:
          0 0 18px 4px var(--fx-color),
          0 0 42px 14px color-mix(in srgb, var(--fx-color) 55%, transparent);
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
           same canvas at these exact coordinates (bottom-left origin) */
        position: absolute;
        left: 14px;
        bottom: 110px;
        width: min(32%, 168px);
        aspect-ratio: 1;
        border: 1px solid
          color-mix(in srgb, var(--border, #e8f1f4) 22%, transparent);
        pointer-events: none;
        z-index: 5;
      }
      .toast {
        position: absolute;
        bottom: 7.5rem;
        left: 50%;
        transform: translateX(-50%);
        z-index: 40;
        padding: 0.5rem 0.9rem;
        border-radius: 999px;
        background: color-mix(
          in srgb,
          var(--primary, #e8f1f4) 92%,
          transparent
        );
        color: var(--primary-foreground, #0a1522);
        font-size: 0.68rem;
        letter-spacing: 0.08em;
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
          color-mix(in srgb, var(--border, #e8f1f4) 22%, transparent);
        border-radius: 2px;
        background: color-mix(
          in srgb,
          var(--background, #03070e) 45%,
          transparent
        );
        color: var(--foreground, #e8f1f4);
        font: inherit;
        font-size: 0.62rem;
        letter-spacing: 0.14em;
        cursor: pointer;
        transition:
          background 0.2s ease,
          color 0.2s ease;
      }
      .chip:hover {
        background: color-mix(
          in srgb,
          var(--foreground, #e8f1f4) 12%,
          transparent
        );
      }
      .chip.active {
        background: var(--primary, #e8f1f4);
        color: var(--primary-foreground, #0a1522);
      }
      .chip.wide {
        min-width: 8rem;
      }
      .chip.sq {
        padding: 0.3rem 0.5rem;
      }
      .dial {
        width: 8.2rem;
        accent-color: var(--primary, #e8f1f4);
      }
      .panel {
        position: absolute;
        top: 0;
        right: 0;
        bottom: 0;
        z-index: 20;
        width: 21rem;
        max-width: 85%;
        padding: 4.4rem 1.4rem 1.4rem;
        border-left: 1px solid
          color-mix(in srgb, var(--border, #e8f1f4) 14%, transparent);
        background: color-mix(
          in srgb,
          var(--background, #02040a) 86%,
          transparent
        );
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
