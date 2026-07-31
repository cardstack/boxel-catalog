// =============================================================================
// TreeEngine — owns the WebGL scene (renderer, cameras, the four render
// passes, camera framing, analytic picking). The isolated component owns
// the tracked UI state and drives this engine through targets/uniforms.
// =============================================================================
// @ts-ignore — CDN module has no type defs
import * as THREE from 'https://cdn.jsdelivr.net/npm/three@0.128.0/+esm';
import {
  TAU,
  V_STEP,
  C_SCALE,
  CENTER_V,
  SPHERE_R,
  HUE_TIERS,
  maxChroma,
  hslToRgb,
  chipHex,
  rgbHex,
  lerpWrapDeg,
  munsellNotation,
  buildArrays,
  type ChipArrays,
} from './munsell';
import {
  VOXEL_VSH,
  VOXEL_FSH,
  HALO_VSH,
  HALO_FSH,
  GRID_VSH,
  GRID_FSH,
  RING_VSH,
  RING_FSH,
} from './shaders';

/* uniforms are shared by all four passes; they live here — with the
   engine — because their camera-basis slots are THREE.Vector3s and this
   module is the single owner of the CDN three import */
export interface Uniforms {
  [key: string]: { value: number | THREE.Vector3 };
}

export function makeUniforms(): Uniforms {
  return {
    uTime: { value: 0 },
    uMorph: { value: 0 },
    uChart: { value: 0 }, // 0 = in the solid, 1 = laid flat as the page
    uChroma: { value: 1 },
    uContrast: { value: 0 },
    uAxis: { value: 0 },
    uGlow: { value: 0.5 },
    uSliceMode: { value: 0 },
    uSlicePos: { value: 0.5 },
    uSliceHalf: { value: 0.24 },
    uHueCount: { value: 20 },
    uCellHue: { value: 1 },
    uCellVal: { value: 1 },
    uScale: { value: 100 },
    uMini: { value: 0 }, // 1 while rendering the scout miniature

    uCamR: { value: new THREE.Vector3(1, 0, 0) },
    uCamU: { value: new THREE.Vector3(0, 1, 0) },
    uCamF: { value: new THREE.Vector3(0, 0, -1) },
    uAnchor: { value: new THREE.Vector3() },
  };
}

/* ═══════════════════════════════════════════════════════════════════════════
   ENGINE — owns the WebGL scene; the component owns the tracked UI state
   ═══════════════════════════════════════════════════════════════════════════ */
export interface PickResult {
  hex: string;
  notation: string;
}

/* the scout miniature's distance is solved once from the solid's full
   extents — it always shows the whole specimen, never zoomed */
const MINI_DIST = (16.6 * 1.18) / Math.tan((25 * Math.PI) / 180);

export class TreeEngine {
  renderer: THREE.WebGLRenderer;
  scene = new THREE.Scene();
  camera = new THREE.PerspectiveCamera(55, 1, 0.2, 600);
  miniCam = new THREE.PerspectiveCamera(50, 1, 0.2, 600);
  miniFwd = new THREE.Vector3();
  miniSize = 150;
  solid = new THREE.Group();
  uniforms = makeUniforms();
  arrays: ChipArrays;
  mesh?: THREE.Mesh;
  halo?: THREE.Points;
  gridMat = new THREE.ShaderMaterial({
    uniforms: this.uniforms,
    vertexShader: GRID_VSH,
    fragmentShader: GRID_FSH,
    transparent: true,
    depthWrite: false,
    depthTest: false,
  });
  ringMat = new THREE.ShaderMaterial({
    uniforms: this.uniforms,
    vertexShader: RING_VSH,
    fragmentShader: RING_FSH,
    transparent: true,
    depthWrite: false,
    depthTest: false,
  });
  gridPts = new THREE.Points(new THREE.BufferGeometry(), this.gridMat);
  ringPts = new THREE.Points(new THREE.BufferGeometry(), this.ringMat);
  canvas: HTMLCanvasElement;
  paused = false;
  morphTarget = 0;
  sliceTarget = 0;
  chartTarget = 0; // 0 = atlas closed · 1 = atlas open (laid flat as the page)
  raf = 0;
  rotY = 0.6;
  rotX = -0.25;
  velY = 0.0015;
  velX = 0;
  baseSpin = 0.0015;
  dist = 46;
  userApproached = false; // a distance the user chose is respected
  tanV = 1; // tan(fov/2) — the page hangs at a size solved from this each frame
  densityIdx = 1;
  disposed = false;

  constructor(canvas: HTMLCanvasElement) {
    this.canvas = canvas;
    this.renderer = new THREE.WebGLRenderer({
      canvas,
      antialias: true,
      alpha: true,
      powerPreference: 'high-performance',
    });
    this.renderer.setClearColor(0x000000, 0);
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.75));
    this.scene.add(this.solid);
    this.gridPts.frustumCulled = false;
    this.ringPts.frustumCulled = false;
    this.gridPts.renderOrder = 2;
    this.ringPts.renderOrder = 3;
    this.scene.add(this.gridPts, this.ringPts);
    this.arrays = buildArrays(HUE_TIERS[this.densityIdx], this.densityIdx);
    this.uniforms.uHueCount.value = HUE_TIERS[this.densityIdx];
    this.uniforms.uSliceHalf.value = Math.PI / HUE_TIERS[this.densityIdx];
    this.buildMesh();
    this.buildGuides();
    this.buildGrid(0, 0.5);
    this.resize();
    // open on the fitted framing immediately, not eased from a guess
    this.dist = this.fitDistance();
    this.loop();
  }

  buildMesh() {
    if (this.mesh) {
      this.solid.remove(this.mesh);
      (this.mesh.geometry as THREE.BufferGeometry).dispose();
      (this.mesh.material as THREE.Material).dispose();
    }
    let a = this.arrays;
    let box = new THREE.BoxGeometry(1, 1, 1);
    let g = new THREE.InstancedBufferGeometry();
    g.index = box.index;
    g.setAttribute('position', box.attributes.position);
    g.setAttribute('normal', box.attributes.normal);
    let add = (name: string, arr: number[], size: number) =>
      g.setAttribute(
        name,
        new THREE.InstancedBufferAttribute(new Float32Array(arr), size),
      );
    add('aTree', a.tree, 3);
    add('aSphere', a.sphere, 3);
    add('aColor', a.cols, 3);
    add('aCFrac', a.cfr, 1);
    add('aAngle', a.ang, 1);
    add('aSeed', a.seed, 1);
    add('aValue', a.val, 1);
    add('aChroma', a.chr, 1);
    add('aEdge', a.edg, 1);
    let mat = new THREE.ShaderMaterial({
      uniforms: this.uniforms,
      vertexShader: VOXEL_VSH,
      fragmentShader: VOXEL_FSH,
    });
    this.mesh = new THREE.Mesh(g, mat);
    this.mesh.frustumCulled = false;
    this.solid.add(this.mesh);
    // the halo pass: one soft point of light per voxel, added not painted
    if (this.halo) {
      this.solid.remove(this.halo);
      (this.halo.geometry as THREE.BufferGeometry).dispose();
      (this.halo.material as THREE.Material).dispose();
    }
    let hg = new THREE.BufferGeometry();
    hg.setAttribute('position', new THREE.Float32BufferAttribute(a.tree, 3));
    hg.setAttribute('aSphere', new THREE.Float32BufferAttribute(a.sphere, 3));
    hg.setAttribute('aColor', new THREE.Float32BufferAttribute(a.cols, 3));
    hg.setAttribute('aCFrac', new THREE.Float32BufferAttribute(a.cfr, 1));
    hg.setAttribute('aAngle', new THREE.Float32BufferAttribute(a.ang, 1));
    hg.setAttribute('aValue', new THREE.Float32BufferAttribute(a.val, 1));
    hg.setAttribute('aChroma', new THREE.Float32BufferAttribute(a.chr, 1));
    hg.setAttribute('aEdge', new THREE.Float32BufferAttribute(a.edg, 1));
    let hmat = new THREE.ShaderMaterial({
      uniforms: this.uniforms,
      vertexShader: HALO_VSH,
      fragmentShader: HALO_FSH,
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
    });
    this.halo = new THREE.Points(hg, hmat);
    this.halo.frustumCulled = false;
    this.solid.add(this.halo);

    // the rings share the halo's per-voxel geometry — same voxels, marked
    // instead of glowed, at their position within the ideal linear grid.
    // Its old geometry is the same object the halo cleanup above just
    // disposed (both pointed at the previous build's hg), so nothing
    // further to free here.
    this.ringPts.geometry = hg;
  }

  buildGuides() {
    // the pedestal: faint rings beneath the tree, and the gray axis
    let ringMat = new THREE.LineBasicMaterial({
      color: 0x16273a,
      transparent: true,
      opacity: 0.8,
    });
    let baseY = -CENTER_V * V_STEP - 1.4;
    for (let c of [4, 8, 12, 16]) {
      let pts: THREE.Vector3[] = [];
      for (let i = 0; i <= 96; i++) {
        let t = (i / 96) * TAU;
        pts.push(
          new THREE.Vector3(
            Math.cos(t) * c * C_SCALE,
            baseY,
            Math.sin(t) * c * C_SCALE,
          ),
        );
      }
      this.solid.add(
        new THREE.Line(new THREE.BufferGeometry().setFromPoints(pts), ringMat),
      );
    }
    let axisPts = [
      new THREE.Vector3(0, -CENTER_V * V_STEP - 1.2, 0),
      new THREE.Vector3(0, (10 - CENTER_V) * V_STEP + 1.2, 0),
    ];
    this.solid.add(
      new THREE.Line(
        new THREE.BufferGeometry().setFromPoints(axisPts),
        new THREE.LineBasicMaterial({
          color: 0x5c7484,
          transparent: true,
          opacity: 0.5,
        }),
      ),
    );
  }

  setDensity(idx: number) {
    this.densityIdx = idx;
    this.arrays = buildArrays(HUE_TIERS[idx], idx);
    this.uniforms.uHueCount.value = HUE_TIERS[idx];
    this.uniforms.uSliceHalf.value = Math.PI / HUE_TIERS[idx];
    this.buildMesh();
    this.buildGrid(this.gridMode, this.gridScrub);
  }

  gridMode = 0;
  gridScrub = 0.5;

  /* the synthetic linear-scale background: a complete conventional grid
     (every saturation × lightness cell filled, whether or not a real
     Munsell chip exists there) for the current cut, rebuilt whenever the
     cut itself changes — hue leaf (mode 1) or value plane (mode 2).
     Takes the TARGET mode/scrub directly rather than reading
     uSliceMode/uSlicePos off the uniforms, since those ease toward their
     target over several frames — reading them synchronously right after
     a mode change would rebuild against a stale, still-mid-transition
     value and leave the wrong background frozen in place once the ease
     finishes (e.g. closing the atlas from VALUE mode would never clear
     the value-mode grid, since nothing calls buildGrid() again after the
     ease settles at mode 0). */
  buildGrid(mode: number, slicePos01: number) {
    this.gridMode = mode;
    this.gridScrub = slicePos01;
    let pos: number[] = [];
    let col: number[] = [];
    if (mode === 1) {
      let phi = slicePos01 * Math.PI;
      let hA = phi / TAU;
      let hB = (hA + 0.5) % 1;
      for (let v = 0; v <= 10; v++) {
        let l = 0.07 + (0.86 * v) / 10;
        let gr = hslToRgb(0, 0, l);
        pos.push(0, v - 5, 0);
        col.push(gr[0], gr[1], gr[2]);
        for (let s = 1; s <= 8; s++) {
          let ra = hslToRgb(lerpWrapDeg(hA), s / 8, l);
          pos.push(s, v - 5, 0);
          col.push(ra[0], ra[1], ra[2]);
          let rb = hslToRgb(lerpWrapDeg(hB), s / 8, l);
          pos.push(-s, v - 5, 0);
          col.push(rb[0], rb[1], rb[2]);
        }
      }
    } else if (mode === 2) {
      let H = HUE_TIERS[this.densityIdx];
      let v = Math.round(slicePos01 * 10);
      let l = 0.07 + (0.86 * v) / 10;
      for (let hi = 0; hi < H; hi++) {
        let deg = lerpWrapDeg(hi / H);
        for (let s = 1; s <= 8; s++) {
          let rgb = hslToRgb(deg, s / 8, l);
          pos.push(hi - H * 0.5 + 0.5, s - 4.5, 0);
          col.push(rgb[0], rgb[1], rgb[2]);
        }
      }
    }
    let g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    g.setAttribute('aCol', new THREE.Float32BufferAttribute(col, 3));
    let old = this.gridPts.geometry;
    this.gridPts.geometry = g;
    old.dispose();
  }

  resize() {
    let w = this.canvas.clientWidth || 1;
    let h = this.canvas.clientHeight || 1;
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
    this.tanV = Math.tan(THREE.MathUtils.degToRad(this.camera.fov / 2));
    // point-size scale for the GRID/RING passes, solved from the same
    // fov math the rest of the page's framing uses
    this.uniforms.uScale.value =
      (h * this.renderer.getPixelRatio() * 0.5) / this.tanV;
    this.miniSize = Math.round(Math.min(w * 0.32, 168));
  }

  /* SOLVE the framing from fov + aspect + the solid's bounding radius,
     blended across the morph — the specimen fills the room by default
     instead of sitting at a fixed distance. Because it can tumble to any
     orientation, the bound is a sphere, never a box. */
  fitDistance(): number {
    let reach = this.uniforms.uChroma.value as number;
    let boundTree = Math.max(12.5, 2.5 + 13.6 * reach);
    let m = this.uniforms.uMorph.value as number;
    let bound = boundTree * (1 - m) + (SPHERE_R + 1.6) * m;
    let dV = (bound * 1.28) / this.tanV;
    let dH = dV / this.camera.aspect;
    return Math.min(Math.max(Math.max(dV, dH), 16), 130);
  }

  tumble(dx: number, dy: number) {
    this.velY = dx * 0.005;
    this.velX = dy * 0.005;
    this.rotY += this.velY;
    this.rotX = Math.max(-1.2, Math.min(1.2, this.rotX + this.velX));
  }

  zoom(delta: number) {
    this.userApproached = true;
    // the far clamp stays close enough that an accidental trackpad
    // scroll can never shrink the specimen to a speck
    this.dist = Math.max(18, Math.min(70, this.dist + delta));
  }

  /* double-click hands the framing back to the auto-fit */
  refit() {
    this.userApproached = false;
  }

  /* the page is analytic, so a click on it can be inverted exactly: screen
     → chart plane → grid cell → Munsell coordinates → the same hex the
     chip was painted with. Only valid while the atlas is open (sliceMode
     off never invert-picks, since there's no page to click). */
  pickHex(cx: number, cy: number): PickResult | null {
    let mode = this.uniforms.uSliceMode.value as number;
    if (mode < 0.5) {
      return null;
    }
    let rect = this.canvas.getBoundingClientRect();
    let ndcX = ((cx - rect.left) / rect.width) * 2 - 1;
    let ndcY = 1 - ((cy - rect.top) / rect.height) * 2;
    let gx = ndcX * this.tanV * this.camera.aspect * this.dist;
    let gy = ndcY * this.tanV * this.dist;
    let ideal = Math.round(this.uniforms.uMorph.value as number) === 1;
    let H = HUE_TIERS[this.densityIdx];
    if (mode > 1.5) {
      let cell = this.uniforms.uCellVal.value as number;
      let v = Math.round((this.uniforms.uSlicePos.value as number) * 10);
      let hIdx = Math.round(gx / cell + H * 0.5 - 0.5);
      if (hIdx < 0 || hIdx >= H) {
        return null;
      }
      let hHue = hIdx / H;
      let row = Math.round(gy / cell + 4.5);
      if (row < 1 || row > 8) {
        return null;
      }
      if (ideal) {
        let [r, g, b] = hslToRgb(
          lerpWrapDeg(hHue),
          row / 8,
          0.07 + (0.86 * v) / 10,
        );
        return {
          hex: rgbHex(r, g, b),
          notation: munsellNotation(hHue, v, (row / 8) * 13),
        };
      }
      let c = 2 * row;
      if (c > maxChroma(hHue, v) + 0.01) {
        return null;
      }
      return {
        hex: chipHex(hHue, v, c),
        notation: munsellNotation(hHue, v, c),
      };
    }
    let cell = this.uniforms.uCellHue.value as number;
    let v = Math.round(gy / cell + 5);
    if (v < 0 || v > 10) {
      return null;
    }
    let u = gx / cell;
    let phi = (this.uniforms.uSlicePos.value as number) * Math.PI;
    let hHue = ((((u >= 0 ? phi : phi + Math.PI) / TAU) % 1) + 1) % 1;
    let col = Math.round(Math.abs(u));
    if (col > 8) {
      return null;
    }
    if (ideal) {
      if (col === 0) {
        let [r, g, b] = hslToRgb(0, 0, 0.07 + (0.86 * v) / 10);
        return { hex: rgbHex(r, g, b), notation: munsellNotation(hHue, v, 0) };
      }
      let [r, g, b] = hslToRgb(
        lerpWrapDeg(hHue),
        col / 8,
        0.07 + (0.86 * v) / 10,
      );
      return {
        hex: rgbHex(r, g, b),
        notation: munsellNotation(hHue, v, (col / 8) * 13),
      };
    }
    if (col === 0) {
      return {
        hex: chipHex(hHue, v, 0),
        notation: munsellNotation(hHue, v, 0),
      };
    }
    let c = 2 * col;
    if (c > maxChroma(hHue, v) + 0.01) {
      return null;
    }
    return { hex: chipHex(hHue, v, c), notation: munsellNotation(hHue, v, c) };
  }

  loop = () => {
    if (this.disposed) {
      return;
    }
    this.raf = requestAnimationFrame(this.loop);
    let u = this.uniforms;
    if (!this.paused) {
      u.uTime.value += 1 / 60;
      this.rotY += this.velY;
      this.velY *= 0.96;
      this.velX *= 0.9;
      if (Math.abs(this.velY) < this.baseSpin + 0.0001) {
        this.velY = this.baseSpin; // the specimen keeps slowly turning at rest
      }
    }
    // spring the morph, slice, and chart (atlas open/close) toward their targets
    u.uMorph.value += (this.morphTarget - (u.uMorph.value as number)) * 0.06;
    u.uSliceMode.value +=
      (this.sliceTarget - (u.uSliceMode.value as number)) * 0.15;
    u.uChart.value += (this.chartTarget - (u.uChart.value as number)) * 0.08;
    u.uAxis.value = -this.rotY + Math.PI * 0.25;
    this.solid.rotation.set(this.rotX, this.rotY, 0);
    if (!this.userApproached) {
      this.dist += (this.fitDistance() - this.dist) * 0.05;
    }
    this.camera.position.set(0, 4, this.dist);
    this.camera.lookAt(0, 0, 0);

    // the page hangs square to the eye, at the solid's depth — its basis
    // is the camera's own right/up/forward, not the tumbling solid's
    let camR = (u.uCamR.value as THREE.Vector3).set(1, 0, 0);
    camR.applyQuaternion(this.camera.quaternion);
    let camU = (u.uCamU.value as THREE.Vector3).set(0, 1, 0);
    camU.applyQuaternion(this.camera.quaternion);
    let camF = (u.uCamF.value as THREE.Vector3).set(0, 0, -1);
    camF.applyQuaternion(this.camera.quaternion);
    (u.uAnchor.value as THREE.Vector3)
      .copy(this.camera.position)
      .addScaledVector(camF, this.dist);

    let hW = 2 * this.dist * this.tanV;
    let wW = hW * this.camera.aspect;
    u.uCellHue.value = Math.min((hW * 0.7) / 11, (wW * 0.84) / 18);
    let H = HUE_TIERS[this.densityIdx];
    u.uCellVal.value = Math.min((hW * 0.7) / 9.5, (wW * 0.84) / (H + 4));

    let cw = this.canvas.clientWidth || 1;
    let chh = this.canvas.clientHeight || 1;
    this.renderer.setViewport(0, 0, cw, chh);
    this.renderer.render(this.scene, this.camera);

    /* the scout: a second small pass from the same bearing, showing the
       whole solid with the current cut lit bright inside it */
    if ((u.uChart.value as number) > 0.02) {
      u.uMini.value = 1;
      this.miniFwd.copy(this.camera.position).normalize();
      this.miniCam.position.copy(this.miniFwd).multiplyScalar(MINI_DIST);
      this.miniCam.lookAt(0, 0, 0);
      this.renderer.setScissorTest(true);
      this.renderer.setScissor(14, 110, this.miniSize, this.miniSize);
      this.renderer.setViewport(14, 110, this.miniSize, this.miniSize);
      this.renderer.render(this.scene, this.miniCam);
      this.renderer.setScissorTest(false);
      u.uMini.value = 0;
    }
  };

  dispose() {
    this.disposed = true;
    cancelAnimationFrame(this.raf);
    this.gridPts.geometry.dispose();
    this.gridMat.dispose();
    this.ringMat.dispose();
    // free every geometry/material still in the scene graph (voxel mesh,
    // halo points, pedestal guide lines) rather than leaning on GC
    this.solid.traverse((obj: THREE.Object3D) => {
      let o = obj as THREE.Mesh;
      o.geometry?.dispose?.();
      if (Array.isArray(o.material)) {
        for (let m of o.material) {
          m.dispose();
        }
      } else {
        o.material?.dispose?.();
      }
    });
    this.renderer.dispose();
  }
}
