import Component from '@glimmer/component';
import { modifier } from 'ember-modifier';

import { loadThree, loadGltfExporter } from '../util/three-loader';
import {
  buildModel,
  nodesFromSpec,
  materialsFromSpec,
  type BuiltModel,
} from '../util/spec-interpreter';

export interface ViewerApi {
  rebuild: () => Promise<void>;
  captureScreenshot: (options?: { frontView?: boolean }) => string | undefined;
  // deterministic multi-angle capture for the review loop: front, side, and
  // three-quarter — 3D errors (thickness, pose) are invisible from one angle.
  // Pass the analysis camera estimate to lead with a reference-angle render.
  captureViews: (camera?: {
    azimuthDeg: number;
    elevationDeg: number;
  }) => string[];
  // serializes the current build to a binary glTF (.glb) — the standard
  // interchange export alongside the editable spec/scene graph
  exportGlb: () => Promise<ArrayBuffer>;
}

interface ModelViewerSignature {
  Args: {
    spec?: any;
    hint?: string;
    onReady?: (api: ViewerApi) => void;
    onWarnings?: (warnings: string[]) => void;
  };
  Element: HTMLElement;
}

function easeOutBack(t: number): number {
  const c1 = 1.70158;
  const c3 = c1 + 1;
  return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2);
}

export default class ModelViewer extends Component<ModelViewerSignature> {
  private THREE: any;
  private renderer: any;
  private scene: any;
  private camera: any;
  private built: BuiltModel | undefined;
  private frame = 0;
  private resizeObserver: ResizeObserver | undefined;
  private lastInteraction = 0;
  private orbit = { theta: 0.85, phi: 1.12, radius: 6 };
  private disposed = false;

  private lastBuiltSpec: any;

  // re-runs whenever the @spec reference changes (e.g. the AI assistant
  // patches currentSpec) so panel-driven edits render live. Skips specs the
  // component already built itself (tasks await rebuild() directly), so a
  // generation round doesn't trigger a duplicate rebuild + pop-in replay.
  syncSpec = modifier((_element: HTMLElement, [spec]: [any]) => {
    if (this.THREE && spec !== undefined && spec !== this.lastBuiltSpec) {
      void this.rebuild();
    }
  });

  setupViewport = modifier((container: HTMLElement) => {
    this.disposed = false;
    let cancelled = false;

    (async () => {
      let THREE = await loadThree();
      if (cancelled) return;
      this.THREE = THREE;

      let renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
      renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
      renderer.outputEncoding = THREE.sRGBEncoding;
      renderer.shadowMap.enabled = true;
      renderer.shadowMap.type = THREE.PCFSoftShadowMap;
      renderer.toneMapping = THREE.ACESFilmicToneMapping;
      renderer.toneMappingExposure = 1.0;
      renderer.domElement.classList.add('viewer-canvas');
      renderer.domElement.setAttribute(
        'aria-label',
        'Interactive 3D reconstruction viewport',
      );
      container.appendChild(renderer.domElement);
      this.renderer = renderer;

      let scene = new THREE.Scene();
      scene.background = new THREE.Color('#0a0b10');
      scene.fog = new THREE.Fog('#0a0b10', 14, 30);
      this.scene = scene;
      // diagnostic handle: lets devtools inspect what materials actually
      // resolved at runtime (data-vs-runtime bugs are invisible otherwise)
      (renderer.domElement as any).__i3dScene = scene;

      let camera = new THREE.PerspectiveCamera(38, 1, 0.1, 100);
      this.camera = camera;

      // three-point-ish rig: warm key, cool fill, rim, soft ambient dome.
      // near-neutral rig: color fidelity beats mood — tinted lights poison
      // both the perceived albedo and the render-vs-reference refine loop
      let defaultRig = new THREE.Group();
      let key = new THREE.DirectionalLight('#fffaf2', 1.2);
      key.position.set(4, 6, 5);
      let fill = new THREE.DirectionalLight('#f2f5ff', 0.45);
      fill.position.set(-5, 2, -2);
      let rim = new THREE.DirectionalLight('#dffbff', 0.25);
      rim.position.set(0, 4, -6);
      let dome = new THREE.HemisphereLight('#5a6070', '#15161c', 0.6);
      defaultRig.add(key, fill, rim, dome);
      scene.add(defaultRig);

      // PMREM environment (hand-rolled mini room: core-only stand-in for
      // examples/RoomEnvironment, which the UMD bundle doesn't ship) — gives
      // metals something real to reflect
      let pmrem = new THREE.PMREMGenerator(renderer);
      let envScene = new THREE.Scene();
      let roomGeo = new THREE.BoxGeometry(10, 10, 10);
      let roomMat = new THREE.MeshBasicMaterial({
        color: '#444444',
        side: THREE.BackSide,
      });
      envScene.add(new THREE.Mesh(roomGeo, roomMat));
      let panelGeo = new THREE.PlaneGeometry(3, 2);
      let panels: [number[], number[], number][] = [
        [[0, 4.9, 0], [-Math.PI / 2, 0, 0], 6],
        [[-4.9, 2, 0], [0, Math.PI / 2, 0], 3],
        [[4.9, 1, -1], [0, -Math.PI / 2, 0], 2],
      ];
      for (let [pos, rot, intensity] of panels) {
        let mat = new THREE.MeshBasicMaterial({ color: '#ffffff' });
        mat.color.multiplyScalar(intensity);
        let panel = new THREE.Mesh(panelGeo, mat);
        panel.position.set(pos[0], pos[1], pos[2]);
        panel.rotation.set(rot[0], rot[1], rot[2]);
        envScene.add(panel);
      }
      scene.environment = pmrem.fromScene(envScene, 0.04).texture;
      pmrem.dispose();

      // star field
      let starCount = 650;
      let positions = new Float32Array(starCount * 3);
      for (let i = 0; i < starCount; i++) {
        let r = 18 + Math.random() * 8;
        let theta = Math.random() * Math.PI * 2;
        let phi = Math.acos(2 * Math.random() - 1);
        positions[i * 3] = r * Math.sin(phi) * Math.cos(theta);
        positions[i * 3 + 1] = r * Math.cos(phi);
        positions[i * 3 + 2] = r * Math.sin(phi) * Math.sin(theta);
      }
      let starGeo = new THREE.BufferGeometry();
      starGeo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
      let starMat = new THREE.PointsMaterial({
        color: '#9fb4e8',
        size: 0.05,
        transparent: true,
        opacity: 0.75,
        sizeAttenuation: true,
      });
      scene.add(new THREE.Points(starGeo, starMat));

      let resize = () => {
        let { clientWidth: w, clientHeight: h } = container;
        if (!w || !h) return;
        renderer.setSize(w, h, false);
        camera.aspect = w / h;
        camera.updateProjectionMatrix();
      };
      this.resizeObserver = new ResizeObserver(resize);
      this.resizeObserver.observe(container);
      resize();

      // hand-rolled orbit: drag to rotate, wheel to zoom
      let dragging = false;
      let lastX = 0;
      let lastY = 0;
      let onPointerDown = (e: PointerEvent) => {
        dragging = true;
        lastX = e.clientX;
        lastY = e.clientY;
        this.lastInteraction = performance.now();
        renderer.domElement.setPointerCapture(e.pointerId);
      };
      let onPointerMove = (e: PointerEvent) => {
        if (!dragging) return;
        this.orbit.theta -= (e.clientX - lastX) * 0.006;
        this.orbit.phi = Math.min(
          Math.PI - 0.15,
          Math.max(0.15, this.orbit.phi - (e.clientY - lastY) * 0.006),
        );
        lastX = e.clientX;
        lastY = e.clientY;
        this.lastInteraction = performance.now();
      };
      let onPointerUp = () => {
        dragging = false;
        this.lastInteraction = performance.now();
      };
      let onWheel = (e: WheelEvent) => {
        e.preventDefault();
        this.orbit.radius = Math.min(
          22,
          Math.max(2, this.orbit.radius * (1 + Math.sign(e.deltaY) * 0.08)),
        );
        this.lastInteraction = performance.now();
      };
      renderer.domElement.addEventListener('pointerdown', onPointerDown);
      renderer.domElement.addEventListener('pointermove', onPointerMove);
      renderer.domElement.addEventListener('pointerup', onPointerUp);
      renderer.domElement.addEventListener('pointercancel', onPointerUp);
      renderer.domElement.addEventListener('wheel', onWheel, {
        passive: false,
      });

      let animate = (now: number) => {
        if (this.disposed) return;
        this.frame = requestAnimationFrame(animate);

        // idle auto-rotate resumes 2.5s after the last interaction
        if (now - this.lastInteraction > 2500) {
          this.orbit.theta += 0.0032;
        }
        let { theta, phi, radius } = this.orbit;
        camera.position.set(
          radius * Math.sin(phi) * Math.sin(theta),
          radius * Math.cos(phi),
          radius * Math.sin(phi) * Math.cos(theta),
        );
        camera.lookAt(0, 0, 0);

        // staggered pop-in for freshly built meshes
        if (this.built) {
          for (let mesh of this.built.meshes) {
            let appear = mesh.userData.appearAt;
            if (appear === undefined) continue;
            let t = (now - appear) / 320;
            if (t < 0) {
              mesh.visible = false;
            } else if (t < 1) {
              mesh.visible = true;
              let s = easeOutBack(Math.max(0.001, t));
              mesh.scale.set(
                mesh.userData.baseScale.x * s,
                mesh.userData.baseScale.y * s,
                mesh.userData.baseScale.z * s,
              );
            } else {
              mesh.visible = true;
              mesh.scale.copy(mesh.userData.baseScale);
              delete mesh.userData.appearAt;
            }
          }
        }

        renderer.render(scene, camera);
      };
      this.frame = requestAnimationFrame(animate);

      await this.rebuild();
      this.args.onReady?.({
        rebuild: () => this.rebuild(),
        captureScreenshot: (options?: { frontView?: boolean }) =>
          this.captureScreenshot(options),
        captureViews: (camera) => this.captureViews(camera),
        exportGlb: () => this.exportGlb(),
      });
    })();

    return () => {
      cancelled = true;
      this.disposed = true;
      cancelAnimationFrame(this.frame);
      this.resizeObserver?.disconnect();
      this.teardownModel();
      if (this.renderer) {
        this.renderer.dispose();
        this.renderer.domElement.remove();
        this.renderer = undefined;
      }
    };
  });

  // center on origin and normalize height so the camera framing holds for
  // any source (spec build or loaded glTF)
  private normalizeIntoView(group: any) {
    let box = new this.THREE.Box3().setFromObject(group);
    if (box.isEmpty()) return;
    let size = new this.THREE.Vector3();
    let center = new this.THREE.Vector3();
    box.getSize(size);
    box.getCenter(center);
    let maxDim = Math.max(size.x, size.y, size.z) || 1;
    let scaleFactor = 2.6 / maxDim;
    group.scale.setScalar(scaleFactor);
    group.position.set(
      -center.x * scaleFactor,
      -center.y * scaleFactor,
      -center.z * scaleFactor,
    );
  }

  private teardownModel() {
    if (this.built) {
      this.built.group.removeFromParent?.();
      this.built.dispose();
      this.built = undefined;
    }
  }

  async rebuild(): Promise<void> {
    if (!this.THREE || !this.scene || this.disposed) return;
    this.lastBuiltSpec = this.args.spec;
    this.teardownModel();

    let spec = this.args.spec;
    let nodes = nodesFromSpec(spec);
    if (!nodes.length) return;
    let built;
    try {
      built = buildModel(this.THREE, nodes, materialsFromSpec(spec), {
        unlit: spec?.inputKind === 'flat-graphic',
      });
    } catch (e) {
      // a build crash must never take the whole card down silently — log the
      // real error and surface it as a warning line
      console.error('i3d buildModel failed:', e);
      this.args.onWarnings?.([`build failed: ${(e as Error)?.message ?? e}`]);
      return;
    }
    this.normalizeIntoView(built.group);

    let now = performance.now();
    built.meshes.forEach((mesh: any, i: number) => {
      mesh.userData.baseScale = mesh.scale.clone();
      mesh.userData.appearAt = now + i * 55;
      mesh.visible = false;
    });

    this.scene.add(built.group);
    this.built = built;
    if (built.warnings.length) {
      this.args.onWarnings?.(built.warnings);
    }
  }

  // binary glTF of the current build — parse() over just the model group so
  // scene furniture (starfield, ground ring, lights) stays out of the file
  async exportGlb(): Promise<ArrayBuffer> {
    if (!this.built?.group) {
      throw new Error('nothing to export — generate a model first');
    }
    let THREE = await loadGltfExporter();
    let exporter = new THREE.GLTFExporter();
    return new Promise((resolve, reject) => {
      exporter.parse(
        this.built!.group,
        (result: ArrayBuffer) => resolve(result),
        (err: unknown) => reject(err),
        { binary: true },
      );
    });
  }

  // fixed angles, restoring the user's orbit afterwards. When the analysis
  // estimated the reference camera, that angle leads the sheet so the
  // review compares like-for-like (the improvement plan's "render from the
  // same camera" stage) — front and side follow for thickness/depth checks.
  captureViews(camera?: {
    azimuthDeg: number;
    elevationDeg: number;
  }): string[] {
    if (!this.renderer || !this.scene || !this.camera) return [];
    let saved = { ...this.orbit };
    let presets = [
      { theta: 0, phi: Math.PI / 2 }, // front
      { theta: Math.PI / 2, phi: Math.PI / 2 }, // side
      { theta: 0.85, phi: 1.12 }, // three-quarter
    ];
    if (camera) {
      // azimuth 0 = straight-on front (+Z); positive = camera to the
      // object's right. phi is the polar angle from +Y.
      let theta = (camera.azimuthDeg * Math.PI) / 180;
      let phi =
        ((90 - Math.min(Math.max(camera.elevationDeg, 0), 80)) * Math.PI) / 180;
      presets.unshift({ theta, phi });
    }
    let shots: string[] = [];
    for (let preset of presets) {
      this.orbit.theta = preset.theta;
      this.orbit.phi = preset.phi;
      let { radius } = this.orbit;
      this.camera.position.set(
        radius * Math.sin(preset.phi) * Math.sin(preset.theta),
        radius * Math.cos(preset.phi),
        radius * Math.sin(preset.phi) * Math.cos(preset.theta),
      );
      this.camera.lookAt(0, 0, 0);
      let shot = this.captureScreenshot();
      if (shot) shots.push(shot);
    }
    this.orbit.theta = saved.theta;
    this.orbit.phi = saved.phi;
    this.lastInteraction = performance.now();
    return shots;
  }

  captureScreenshot(options?: { frontView?: boolean }): string | undefined {
    if (!this.renderer || !this.scene || !this.camera) return undefined;
    // flat artwork must be judged head-on, not from an arbitrary orbit angle
    if (options?.frontView) {
      this.orbit.theta = 0;
      this.orbit.phi = Math.PI / 2;
      this.lastInteraction = performance.now();
      let { radius } = this.orbit;
      this.camera.position.set(0, 0, radius);
      this.camera.lookAt(0, 0, 0);
    }
    // fast-forward the pop-in stagger so every mesh is in its final state
    if (this.built) {
      for (let mesh of this.built.meshes) {
        if (mesh.userData.appearAt !== undefined) {
          mesh.visible = true;
          if (mesh.userData.baseScale) mesh.scale.copy(mesh.userData.baseScale);
          delete mesh.userData.appearAt;
        }
      }
    }
    this.renderer.render(this.scene, this.camera);
    return this.renderer.domElement.toDataURL('image/webp', 0.9);
  }

  <template>
    <div
      class='viewer'
      {{this.setupViewport}}
      {{this.syncSpec @spec}}
      ...attributes
    >
      {{#if @hint}}
        <p class='viewer-hint'>{{@hint}}</p>
      {{/if}}
      <p class='viewer-controls-hint'>drag to orbit · scroll to zoom</p>
    </div>
    <style scoped>
      .viewer {
        position: relative;
        width: 100%;
        height: 100%;
        min-height: 0;
        overflow: hidden;
        background: var(--i3d-bg, var(--background, #0a0b10));
      }
      .viewer :deep(.viewer-canvas) {
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
        display: block;
        touch-action: none;
      }
      .viewer-hint {
        position: absolute;
        z-index: 1;
        top: 50%;
        left: 50%;
        transform: translate(-50%, -50%);
        margin: 0;
        font-family: var(--mono, ui-monospace, Menlo, monospace);
        font-size: 0.8125rem;
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: var(--i3d-text-dim, var(--muted-foreground, #9aa0b2));
        pointer-events: none;
      }
      .viewer-controls-hint {
        position: absolute;
        z-index: 1;
        right: 0.75rem;
        bottom: 0.625rem;
        margin: 0;
        padding: 0.25rem 0.625rem;
        border: 1px solid var(--i3d-border, var(--border, #232838));
        border-radius: 0.5rem;
        background: rgba(20, 22, 31, 0.62);
        font-family: var(--mono, ui-monospace, Menlo, monospace);
        font-size: 0.6875rem;
        color: var(--i3d-text-dim, var(--muted-foreground, #9aa0b2));
        pointer-events: none;
      }
    </style>
  </template>
}
