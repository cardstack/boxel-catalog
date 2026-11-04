/**
 * THE PICTURE, IN DEPTH. One camera films three layers:
 *
 *   back   — the shot's photo, full-bleed, at z = 0
 *   type   — the lyric layer (DOM), at z = TYPE_Z, placed by `typeTransform`
 *   front  — her cutout, at z = CUT_Z, drawn over the type
 *
 * so a pan or a push moves each layer by its own amount, and the words pass
 * behind her where they cross. The back canvas carries the look (the cyan and
 * red split on the kick, restrained highlight bloom, liquid-glass seams
 * between shots); the front canvas carries only her, with the same split.
 *
 * three.js renders with WebGPU where the browser has it and WebGL2 where it
 * does not, and is imported on demand, so a card that cannot load it still
 * shows its lyrics.
 */
import {
  CUTOUTS,
  framing,
  MIRROR,
  PHOTOS,
  type Photo,
  type Pose,
} from './song-clock';

const THREE_URL = 'https://esm.sh/three@0.185.1/webgpu';
const TSL_URL = 'https://esm.sh/three@0.185.1/tsl';

/** vertical field of view, degrees */
const FOV = 32;
/** a photo is 16 × 9 scene units */
const W = 16;
const H = 9;
/** how far in front of the photo her cutout floats */
export const CUT_Z = 1.4;
/** and the type, between the two */
export const TYPE_Z = 0.7;

export interface PictureFrame {
  /** the outgoing and incoming shot; `mix` 0 → 1 across the seam */
  from: Photo;
  to: Photo;
  mix: number;
  /** 0 dissolve, 1 glass, 2 whip, 3 glitch */
  seam: number;
  pose: Pose;
  /** the outgoing shot's own camera, while a seam crosses to `to` */
  poseFrom?: Pose;
  /** the kick, 0..1 */
  kick: number;
  /** a flash at a section head, 0..1 */
  flash: number;
  /** seconds, for the seams' moving refraction */
  time: number;
}

/** three.js from esm.sh has no types in the realm */
type Three = any;

/**
 * The distance at which a photo covers the frame, and where the frame sits
 * on it: centred on her face as far as the photo allows, so a tall frame
 * never crops her head and a push closes in on her face, not her coat.
 */
function cover(aspect: number, fx: number, fy = 0.35, dolly = 1) {
  const tanHalf = Math.tan((FOV * Math.PI) / 360);
  const d = aspect > W / H ? W / 2 / (tanHalf * aspect) : H / 2 / tanHalf;
  const visibleH = 2 * tanHalf * d * dolly;
  const visibleW = visibleH * aspect;
  const slackX = Math.max(0, W - visibleW) / 2;
  const slackY = Math.max(0, H - visibleH) / 2;
  // the face a third of the way down the frame
  const x = Math.max(-slackX, Math.min(slackX, (fx - 0.5) * W));
  const y = Math.max(-slackY, Math.min(slackY, (0.5 - fy) * H - visibleH / 6));
  return { d, x, y, slackX, slackY };
}

interface Layers {
  plate: any;
  /** the plate's texture, its standard image, and its HD image while near */
  tex?: any;
  low?: unknown;
  hd?: unknown;
  loading?: boolean;
  cut?: any;
  cutFront?: any;
}

/** a phone or a small laptop: fewer pixels and a lighter look */
export const LOW_POWER =
  typeof navigator !== 'undefined' &&
  ((navigator.hardwareConcurrency || 8) <= 4 ||
    ((navigator as Navigator & { deviceMemory?: number }).deviceMemory ?? 8) <=
      4 ||
    matchMedia('(pointer: coarse)').matches);

export class DepthPicture {
  ready: Promise<void>;
  failed = false;
  /** device pixels per CSS pixel the picture renders at; lowered when frames run long */
  ratio = Math.min(window.devicePixelRatio || 1, LOW_POWER ? 1.5 : 2);
  /** the cheap pipeline holds the frame between seams */
  private still: any;
  private frontDrawn = true;
  private useFront = false;

  private back: any;
  private front: any;
  private pipeline: any;
  private sceneA: any;
  private sceneB: any;
  private frontScene: any;
  private camera: any;
  private cameraB: any;
  private layers = new Map<Photo, Layers>();
  private u: Record<string, any> = {};
  private width = 1;
  private height = 1;
  private shownA?: Photo;
  private shownB?: Photo;

  constructor(
    private backCanvas: HTMLCanvasElement,
    private frontCanvas: HTMLCanvasElement,
    private url: (path: string) => string,
  ) {
    this.ready = this.init().catch((e) => {
      this.failed = true;
      console.error('lyric-video: the picture could not start', e);
    });
  }

  private async init(): Promise<void> {
    const THREE: Three = await import(/* @vite-ignore */ THREE_URL);
    const TSL: any = await import(/* @vite-ignore */ TSL_URL);

    this.back = new THREE.WebGPURenderer({
      canvas: this.backCanvas,
      antialias: true,
    });
    this.front = new THREE.WebGPURenderer({
      canvas: this.frontCanvas,
      antialias: true,
      alpha: true,
    });
    await Promise.all([this.back.init(), this.front.init()]);
    for (const r of [this.back, this.front]) {
      r.setPixelRatio(this.ratio);
      r.outputColorSpace = THREE.SRGBColorSpace;
    }
    this.front.setClearColor(0x000000, 0);

    this.sceneA = new THREE.Scene();
    this.sceneB = new THREE.Scene();
    this.frontScene = new THREE.Scene();
    // each shot of a seam under its own camera, so neither reframes midway
    this.camera = new THREE.PerspectiveCamera(FOV, 16 / 9, 0.05, 200);
    this.cameraB = new THREE.PerspectiveCamera(FOV, 16 / 9, 0.05, 200);

    const {
      uniform,
      texture,
      uv,
      vec2,
      vec3,
      vec4,
      float,
      sin,
      fract,
      dot,
      mix,
      smoothstep,
      max,
      clamp,
      floor,
      step,
      mx_noise_float,
    } = TSL;
    const u = {
      mix: uniform(0),
      seam: uniform(0),
      split: uniform(0.0015),
      flash: uniform(0),
      time: uniform(0),
      pump: uniform(1),
    };
    this.u = u;

    // the photos and her cutouts, loaded once
    const loader = new THREE.TextureLoader();
    // the front layer (her cutout over the type) only if its canvas is shown
    // at all: hidden, it costs a second renderer and every cutout for nothing
    const cs = getComputedStyle(this.frontCanvas);
    this.useFront =
      cs.display !== 'none' &&
      cs.visibility !== 'hidden' &&
      this.frontCanvas.offsetParent !== null;
    const wantCuts = this.useFront;
    const plate = new THREE.PlaneGeometry(W, H);
    await Promise.all(
      PHOTOS.map(async (p) => {
        const tex = await loader.loadAsync(this.url(`${p}.jpg`));
        tex.colorSpace = THREE.SRGBColorSpace;
        tex.anisotropy = 8;
        const img = tex.image as { width: number; height: number };
        const aspect = img.width / img.height;
        if (aspect < W / H) {
          // the square cover: crop it like object-fit: cover
          tex.repeat.set(1, aspect / (W / H));
          tex.offset.set(0, (1 - tex.repeat.y) / 2);
        }
        const entry: Layers = {
          plate: new THREE.Mesh(
            plate,
            new THREE.MeshBasicNodeMaterial({ map: tex }),
          ),
          tex,
          low: tex.image,
        };
        // her cutouts only if the layer that draws them is shown at all
        if (wantCuts && CUTOUTS.has(p)) {
          const name = p.split('/')[1];
          const ct = await loader
            .loadAsync(this.url(`cut/${name}.webp`))
            .catch(() => null);
          if (ct) {
            ct.colorSpace = THREE.SRGBColorSpace;
            const makeCut = () => {
              const m = new THREE.MeshBasicNodeMaterial({
                transparent: true,
                depthWrite: false,
              });
              const off = vec2(u.split, 0);
              const t = texture(ct);
              m.colorNode = vec4(
                t.sample(uv().add(off)).r,
                t.sample(uv()).g,
                t.sample(uv().sub(off)).b,
                t.sample(uv()).a,
              );
              const mesh = new THREE.Mesh(plate, m);
              // nearer the lens, scaled so it registers with the plate at rest
              mesh.position.z = CUT_Z;
              return mesh;
            };
            entry.cut = makeCut();
            entry.cutFront = makeCut();
          }
        }
        if (MIRROR.has(p)) {
          // mirrored shots: the plate and her cutouts flip together
          for (const m of [entry.plate, entry.cut, entry.cutFront])
            if (m) m.scale.x = -1;
        }
        this.layers.set(p, entry);
      }),
    );

    // COMPOSITE: two shots, a seam between them, and the look
    const a = TSL.pass(this.sceneA, this.camera).getTextureNode('output');
    const b = TSL.pass(this.sceneB, this.cameraB).getTextureNode('output');
    const p0 = uv().sub(0.5).div(u.pump).add(0.5);

    // the seam's moving refraction field
    const q = (o: any) =>
      mx_noise_float(vec3(o.mul(vec2(3.2, 5.0)), u.time.mul(0.35)));
    const n = q(p0);
    const e = 0.004;
    const nx = q(p0.add(vec2(e, 0))).sub(n);
    const ny = q(p0.add(vec2(0, e))).sub(n);
    const bend = sin(u.mix.mul(Math.PI));
    const isGlass = step(0.5, u.seam).mul(step(u.seam, 1.5));
    const isWhip = step(1.5, u.seam).mul(step(u.seam, 2.5));
    const isGlitch = step(2.5, u.seam);
    const refr = vec2(nx, ny).mul(bend).mul(isGlass.mul(5).add(0.6));
    // a whip smears along x; a glitch pushes some bands sideways
    const band = floor(p0.y.mul(36));
    const h = fract(
      sin(band.mul(91.7).add(floor(u.time.mul(24)))).mul(43758.547),
    );
    const glitch = h
      .sub(0.5)
      .mul(0.14)
      .mul(step(0.55, fract(h.mul(7.3))))
      .mul(bend)
      .mul(isGlitch);
    const whip = bend.mul(isWhip).mul(0.06);
    const pa = p0.add(refr).add(vec2(glitch.add(whip), 0));
    const pb = p0.sub(refr).add(vec2(glitch.sub(whip), 0));
    // the signature split: red and blue pushed apart, wider in a seam
    const s = u.split.add(bend.mul(0.006));
    const rgb = (tex: any, at: any) =>
      vec3(
        tex.sample(at.add(vec2(s, 0))).r,
        tex.sample(at).g,
        tex.sample(at.sub(vec2(s, 0))).b,
      );
    const colA = rgb(a, pa);
    const colB = rgb(b, pb);
    // which pixels have crossed: glass follows the refraction field, a
    // dissolve lets the incoming shot's highlights cross first
    const lumB = dot(colB, vec3(0.299, 0.587, 0.114));
    const field = mix(
      lumB.mul(0.7).add(n.mul(0.3).add(0.15)),
      n.mul(0.5).add(0.5).mul(0.6).add(p0.x.mul(0.4)),
      isGlass,
    );
    const crossed = smoothstep(
      field.sub(0.18),
      field.add(0.18),
      u.mix.mul(1.36).sub(0.18),
    );
    let col = mix(colA, colB, crossed);

    // restrained bloom: a short streak off the brightest light, cyan to
    // the left, red to the right
    let streak = vec3(0, 0, 0);
    const taps = LOW_POWER ? 0 : 3;
    for (let k = 1; k <= taps; k++) {
      const o = vec2(k * 0.022, 0);
      const wgt = 0.24 / k;
      const left = max(rgb(a, p0.sub(o)).sub(0.8), 0);
      const right = max(rgb(a, p0.add(o)).sub(0.8), 0);
      streak = streak
        .add(left.mul(vec3(0.35, 0.9, 1.0)).mul(wgt))
        .add(right.mul(vec3(1.0, 0.35, 0.4)).mul(wgt));
    }
    col = col.add(streak.mul(float(1).sub(crossed.mul(0.5))));
    // grade: soft highlight rolloff, clean blacks, a restrained vignette
    const grade = (x: any) => {
      const g = x.div(x.mul(0.12).add(1)).mul(1.06);
      const c = uv().sub(0.5);
      return vec4(
        clamp(g.mul(float(1).sub(dot(c, c).mul(0.35))).add(u.flash), 0, 1),
        1,
      );
    };
    const pipeline = new THREE.RenderPipeline(this.back);
    pipeline.outputNode = grade(col);
    this.pipeline = pipeline;

    // between seams (most of the song) one shot, its split, the grade: no
    // noise field, no second pass
    let held = rgb(a, p0);
    let glow = vec3(0, 0, 0);
    for (let k = 1; k <= taps; k++) {
      const o = vec2(k * 0.022, 0);
      const wgt = 0.24 / k;
      glow = glow
        .add(
          max(rgb(a, p0.sub(o)).sub(0.8), 0)
            .mul(vec3(0.35, 0.9, 1.0))
            .mul(wgt),
        )
        .add(
          max(rgb(a, p0.add(o)).sub(0.8), 0)
            .mul(vec3(1.0, 0.35, 0.4))
            .mul(wgt),
        );
    }
    held = held.add(glow);
    const still = new THREE.RenderPipeline(this.back);
    still.outputNode = grade(held);
    this.still = still;
    this.resize(this.width, this.height);
  }

  resize(width: number, height: number): void {
    this.width = Math.max(1, width);
    this.height = Math.max(1, height);
    // before the pipeline exists the size is only recorded; init applies it
    if (!this.pipeline) return;
    for (const r of [this.back, this.front])
      r.setSize(this.width, this.height, false);
    for (const c of [this.camera, this.cameraB]) {
      c.aspect = this.width / this.height;
      c.updateProjectionMatrix();
    }
  }

  private stage(scene: any, photo: Photo) {
    const entry = this.layers.get(photo);
    if (!entry) return;
    // the photo alone: a cutout on its own plane drifts off her under the
    // camera and reads as a plain double. The only doubling is the
    // colour-separated cyan/red split of the whole frame, as on the cover.
    scene.add(entry.plate);
  }

  /** the camera for a pose, in the shot's own space (the photo at the origin) */
  private place(camera: any, pose: Pose, photo: Photo) {
    const aspect = this.width / this.height;
    const tall = aspect < 1;
    const f = framing(photo);
    // a tall frame is already close on her: pushes stay small there. A wide
    // frame pushes in on the wide shots, so she is big, like an editorial page
    const zoom = tall ? 1 : f.zoom;
    const dolly = (tall ? Math.max(0.89, pose.dolly) : pose.dolly) * zoom;
    const {
      d,
      x: centred,
      y: fy,
      slackX,
      slackY,
    } = cover(aspect, f.fx, f.fy, dolly);
    let fx = centred;
    if (zoom < 1) {
      // her face on the third line on her own side, the other two thirds open
      const visibleW = 2 * Math.tan((FOV * Math.PI) / 360) * d * dolly * aspect;
      const side = Math.sign(f.fx - 0.5) || 1;
      fx = Math.max(
        -slackX,
        Math.min(slackX, (f.fx - 0.5) * W - (side * visibleW) / 6),
      );
    }
    const dist = d * dolly;
    const yaw = (pose.yaw * Math.PI) / 180;
    const pitch = (pose.pitch * Math.PI) / 180;
    // the drift stays inside the photo
    const aim = {
      x: Math.max(-slackX, Math.min(slackX, fx + pose.x * H)),
      y: Math.max(-slackY, Math.min(slackY, fy + pose.y * H)),
    };
    camera.position.set(
      aim.x + Math.sin(yaw) * Math.cos(pitch) * dist,
      aim.y + Math.sin(pitch) * dist,
      Math.cos(yaw) * Math.cos(pitch) * dist,
    );
    camera.lookAt(aim.x, aim.y, 0);
  }

  /**
   * The CSS transform that puts the type layer at TYPE_Z under this camera:
   * a plane nearer the lens slides further on a pan and grows on a push.
   */
  typeTransform(pose: Pose, photo: Photo): string {
    const aspect = this.width / this.height;
    const { d } = cover(aspect, framing(photo).fx);
    // the words ride the camera only in part, so a big push doesn't balloon them
    const dollyT =
      1 - (1 - (aspect < 1 ? Math.max(0.89, pose.dolly) : pose.dolly)) * 0.3;
    const dist = d * dollyT;
    const grow = (d - TYPE_Z) / Math.max(0.1, dist - TYPE_Z);
    const pxPerUnit =
      this.height / (2 * Math.tan((FOV * Math.PI) / 360) * (d - TYPE_Z));
    const lead = TYPE_Z / d;
    const dx = -pose.x * H * lead * pxPerUnit;
    const dy = pose.y * H * lead * pxPerUnit;
    return `translate3d(${dx.toFixed(2)}px, ${dy.toFixed(2)}px, 0) rotateY(${(-pose.yaw * 0.5).toFixed(3)}deg) rotateX(${(pose.pitch * 0.5).toFixed(3)}deg) scale(${grow.toFixed(4)})`;
  }

  paint(f: PictureFrame): void {
    if (!this.pipeline || this.failed) return;
    if (this.shownA !== f.from || this.shownB !== f.to) {
      this.sceneA.clear();
      this.sceneB.clear();
      this.stage(this.sceneA, f.from);
      if (f.to !== f.from) this.stage(this.sceneB, f.to);
      this.shownA = f.from;
      this.shownB = f.to;
    }
    const photo = f.mix > 0.5 ? f.to : f.from;
    // the outgoing shot keeps its own move; the incoming one starts its own
    this.place(
      this.camera,
      f.to === f.from ? f.pose : (f.poseFrom ?? f.pose),
      f.from,
    );
    this.place(this.cameraB, f.pose, f.to);
    this.u.mix.value = f.to === f.from ? 0 : f.mix;
    this.u.seam.value = f.seam;
    this.u.split.value = 0.0012;
    this.u.flash.value = f.flash;
    this.u.time.value = f.time;
    this.u.pump.value = 1;
    // (a seam's first frame is still the outgoing shot alone)
    const seaming = f.to !== f.from && f.mix > 0;
    (seaming ? this.pipeline : this.still).render();

    // her, over the type: whichever shot holds the frame, faded across a
    // seam. Nothing to draw (or the layer hidden): draw nothing, once
    const entry = this.layers.get(photo);
    const shown = this.useFront && !!entry?.cutFront;
    if (!shown && !this.frontDrawn) return;
    this.frontScene.clear();
    if (shown && entry?.cutFront) {
      entry.cutFront.material.opacity =
        f.to === f.from ? 1 : Math.abs(f.mix - 0.5) * 2;
      this.frontScene.add(entry.cutFront);
    }
    this.front.render(
      this.frontScene,
      photo === f.from ? this.camera : this.cameraB,
    );
    this.frontDrawn = shown;
  }

  /**
   * Sharper photos on a big screen, only while they are near: the shots
   * about to be on screen get their HD image (decoded off the main thread,
   * swapped in while they are not showing); the rest go back to the
   * standard one, so the GPU only ever holds a few large textures.
   * Phones keep the standard images.
   */
  prefetch(near: Photo[]): void {
    if (LOW_POWER || !this.pipeline) return;
    const want = new Set(near);
    const showing = (p: Photo) => p === this.shownA || p === this.shownB;
    for (const [p, e] of this.layers) {
      if (!e.tex) continue;
      if (want.has(p)) {
        if (!e.hd && !e.loading) {
          e.loading = true;
          const img = new Image();
          img.crossOrigin = 'anonymous';
          img.src = this.url(`hd/${p}.jpg`);
          void img
            .decode()
            .then(() => (e.hd = img))
            .catch(() => {})
            .finally(() => (e.loading = false));
        }
        if (e.hd && e.tex.image !== e.hd && !showing(p)) {
          e.tex.image = e.hd;
          e.tex.needsUpdate = true;
        }
      } else if (e.tex.image !== e.low && !showing(p)) {
        e.tex.image = e.low;
        e.tex.needsUpdate = true;
        e.hd = undefined;
      }
    }
  }

  /** fewer device pixels, when frames run long */
  lower(): boolean {
    const next = Math.max(1, Math.round((this.ratio - 0.25) * 4) / 4);
    if (next === this.ratio || !this.back) return false;
    this.ratio = next;
    for (const r of [this.back, this.front]) r.setPixelRatio(next);
    this.resize(this.width, this.height);
    return true;
  }

  destroy(): void {
    this.back?.dispose();
    this.front?.dispose();
  }
}
