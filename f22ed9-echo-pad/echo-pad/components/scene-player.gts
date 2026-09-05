import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { modifier } from 'ember-modifier';

import PlayIcon from '@cardstack/boxel-icons/play';
import { eq } from '@cardstack/boxel-ui/helpers';

import {
  compileExpression,
  validateSceneSpec,
  type SceneAddStep,
  type ScenePlayStep,
  type SceneSpec,
} from '../utils/scene';

type ManimRuntime = Record<string, any>;

// only one scene plays at a time — a board full of projection slips must not
// hold a WebGL context per slip
let stopCurrent: (() => void) | null = null;

const SCREEN_BG = '#0b0d12';
const SCREEN_ACCENT = '#c8ff3d';
const PAPER_BG = '#f7f4ec';
const PAPER_ACCENT = '#c33d2e';
const INK_BLUE = '#2b3f8c';

async function runScene(
  M: ManimRuntime,
  scene: {
    add(...o: unknown[]): void;
    play(...a: unknown[]): Promise<void>;
    wait(d?: number): Promise<void>;
  },
  spec: SceneSpec,
): Promise<void> {
  let objects = new Map<string, any>();
  let introduced = new Set<string>();

  let accent = spec.background === 'paper' ? PAPER_ACCENT : SCREEN_ACCENT;
  let build = (step: SceneAddStep): any => {
    let color =
      step.color === 'accent' || !step.color ? accent : (step.color as string);
    switch (step.add) {
      case 'ink': {
        let lines = spec.ink;
        if (!Array.isArray(lines) || !lines.length) {
          return null;
        }
        let parts = lines
          .map((l) => {
            let pts: number[][] = [];
            for (let i = 0; i + 1 < l.length; i += 2) {
              pts.push([l[i], l[i + 1], 0]);
            }
            if (pts.length < 2) {
              return null;
            }
            let v = new M.VMobject();
            v.setPointsAsCorners(pts);
            // hand ink is a stroke, never a filled shape
            (v as any).fillOpacity = 0;
            (v as any).strokeWidth = 3;
            return v;
          })
          .filter(Boolean);
        if (!parts.length) {
          return null;
        }
        let g = new M.VGroup(...parts);
        g.setColor?.(
          step.color && step.color !== 'accent'
            ? (step.color as string)
            : INK_BLUE,
        );
        return g;
      }
      case 'axes':
        return new M.Axes({
          xRange: [...(step.xRange as number[]), 1],
          yRange: [...(step.yRange as number[]), 1],
          xLength: 10,
          yLength: 5.5,
          color: '#667080',
          tips: false,
        });
      case 'plane':
        return new M.NumberPlane({
          xRange: step.xRange,
          yRange: step.yRange,
          xLength: 10,
          yLength: 6,
          color: '#596170',
          backgroundLineStyle: {
            color: '#303541',
            opacity: 0.6,
            strokeWidth: 1,
          },
        });
      case 'graph': {
        let fn = compileExpression(String(step.fn));
        if (!fn) {
          return null;
        }
        let axes = step.axes ? objects.get(String(step.axes)) : undefined;
        return new M.FunctionGraph({
          func: fn,
          xRange: step.xRange,
          color,
          ...(axes ? { axes } : {}),
        });
      }
      case 'circle':
        return new M.Circle({
          radius: step.radius,
          color,
          strokeWidth: 3,
          fillOpacity: 0.1,
        });
      case 'square':
        return new M.Square({
          sideLength: step.side,
          color,
          fillOpacity: 0.12,
        });
      case 'rect':
        return new M.Rectangle({
          width: step.w,
          height: step.h,
          color,
          fillOpacity: 0.12,
        });
      case 'line':
        return new M.Line({
          start: [...(step.from as number[]), 0],
          end: [...(step.to as number[]), 0],
          color,
        });
      case 'arrow':
        return new M.Arrow({
          start: [...(step.from as number[]), 0],
          end: [...(step.to as number[]), 0],
          color,
        });
      case 'vector':
        return new M.Vector({
          direction: [...(step.to as number[]), 0],
          color,
        });
      case 'dot':
        return new M.Dot({
          point: [...(step.at as number[]), 0],
          radius: step.radius,
          color,
        });
      case 'text': {
        let t = new M.Text(String(step.value));
        t.setColor?.(color);
        return t;
      }
      case 'mathtex': {
        let t = new M.MathTex({ latex: String(step.value) });
        t.setColor?.(color);
        return t;
      }
      default:
        return null;
    }
  };

  for (let step of spec.steps) {
    if ('add' in step && typeof step.add === 'string') {
      let s = step as SceneAddStep;
      try {
        let obj = build(s);
        if (!obj) {
          continue;
        }
        if (s.at && s.add !== 'dot') {
          obj.moveTo?.([...(s.at as number[]), 0]);
        }
        objects.set(s.id, obj);
      } catch {
        // one bad mobject never kills the scene
      }
      continue;
    }
    let p = step as ScenePlayStep;
    let d = Number(p.duration) || 1;
    if (p.play === 'wait') {
      await scene.wait(d);
      continue;
    }
    let obj = p.target ? objects.get(p.target) : undefined;
    if (!obj) {
      continue;
    }
    try {
      let intro = ['create', 'write', 'fadeIn'].includes(p.play);
      if (!intro && !introduced.has(p.target!)) {
        scene.add(obj);
        introduced.add(p.target!);
      }
      switch (p.play) {
        case 'create':
          await scene.play(new M.Create(obj, { duration: d }));
          break;
        case 'write':
          await scene.play(new M.Write(obj, { duration: d }));
          break;
        case 'fadeIn':
          await scene.play(new M.FadeIn(obj, { duration: d }));
          break;
        case 'fadeOut':
          await scene.play(new M.FadeOut(obj, { duration: d }));
          break;
        case 'transform': {
          let to = objects.get(String(p.to));
          if (to) {
            await scene.play(new M.Transform(obj, to, { duration: d }));
          }
          break;
        }
        case 'rotate':
          await scene.play(new M.Rotate(obj, { angle: p.angle, duration: d }));
          break;
        case 'scale':
          await scene.play(
            new M.Scale(obj, { scaleFactor: p.factor, duration: d }),
          );
          break;
        case 'wave':
          await scene.play(
            new M.ApplyWave(obj, {
              amplitude: p.amplitude,
              duration: d,
              direction: 'vertical',
            }),
          );
          break;
        case 'orbit': {
          let path = objects.get(String(p.path));
          if (path) {
            await scene.play(new M.MoveAlongPath(obj, { path, duration: d }));
          }
          break;
        }
        case 'indicate':
          await scene.play(new M.Indicate(obj, { duration: d }));
          break;
        case 'shear': {
          let m2 = p.matrix as number[][];
          await scene.play(
            new M.ApplyMatrix(obj, {
              matrix: [
                [m2[0][0], m2[0][1], 0],
                [m2[1][0], m2[1][1], 0],
                [0, 0, 1],
              ],
              duration: d,
            }),
          );
          break;
        }
      }
      if (intro) {
        introduced.add(p.target!);
      }
    } catch {
      // skip a failing step; the rest of the scene still plays
    }
  }
}

interface Signature {
  Args: { sceneJson?: string | null };
  Element: HTMLElement;
}

export class EchoScenePlayer extends Component<Signature> {
  @tracked status: 'poster' | 'active' | 'error' = 'poster';

  get spec(): SceneSpec | null {
    try {
      return validateSceneSpec(JSON.parse(this.args.sceneJson ?? ''));
    } catch {
      return null;
    }
  }

  get title(): string {
    return this.spec?.title ?? 'Animation';
  }

  get background(): string {
    return this.spec?.background ?? 'screen';
  }

  stopEvent = (e: Event) => {
    e.stopPropagation();
  };

  play = () => {
    if (!this.spec) {
      this.status = 'error';
      return;
    }
    stopCurrent?.();
    this.status = 'active';
  };

  stop = () => {
    this.status = 'poster';
  };

  willDestroy(): void {
    super.willDestroy();
    if (stopCurrent === this.stop) {
      stopCurrent = null;
    }
  }

  mountPlayer = modifier((element: HTMLElement) => {
    let active = true;
    let player: { dispose(): void } | undefined;
    stopCurrent = this.stop;

    void (async () => {
      try {
        // lazy: ink-only boards never pay for the manim bundle
        // @ts-expect-error the pinned realm bundle ships as untyped browser JS
        let M = (await import('../manim-web')) as unknown as ManimRuntime;
        if (!active) {
          return;
        }
        player = new M.Player(element, {
          autoHideMs: 2600,
          autoPlay: true,
          loop: false,
          backgroundColor:
            this.spec!.background === 'paper' ? PAPER_BG : SCREEN_BG,
        });
        await (player as any).sequence(async (scene: any) =>
          runScene(M, scene, this.spec!),
        );
      } catch {
        if (active) {
          this.status = 'error';
        }
      }
    })();

    return () => {
      active = false;
      player?.dispose();
      element.replaceChildren();
      if (stopCurrent === this.stop) {
        stopCurrent = null;
      }
    };
  });

  <template>
    {{! a drawing surface: strokes start on pointerdown, overlays absorb it }}
    {{! template-lint-disable no-pointer-down-event-binding }}
    <div
      class='echo-scene'
      data-state={{this.status}}
      data-bg={{this.background}}
      ...attributes
    >
      {{#if (eq this.status 'active')}}
        <div
          class='mount'
          {{this.mountPlayer}}
          {{on 'pointerdown' this.stopEvent}}
        ></div>
        <button
          type='button'
          class='scene-stop'
          aria-label='Close animation'
          {{on 'click' this.stop}}
          {{on 'pointerdown' this.stopEvent}}
        >✕</button>
      {{else}}
        <button
          type='button'
          class='poster'
          aria-label='Play animation: {{this.title}}'
          {{on 'click' this.play}}
          {{on 'pointerdown' this.stopEvent}}
        >
          <PlayIcon class='glyph' />
          <span class='scene-title'>{{this.title}}</span>
          {{#if (eq this.status 'error')}}
            <span class='scene-err'>could not play — tap to retry</span>
          {{/if}}
        </button>
      {{/if}}
    </div>
    <style scoped>
      .echo-scene {
        position: relative;
        width: 100%;
        height: 100%;
        min-height: 180px;
        background: #0b0d12;
        overflow: hidden;
      }
      .mount {
        width: 100%;
        height: 100%;
        min-height: inherit;
      }
      .poster {
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 10px;
        width: 100%;
        height: 100%;
        min-height: inherit;
        border: none;
        background:
          radial-gradient(
            80% 70% at 50% 40%,
            rgba(200, 255, 61, 0.06),
            transparent 70%
          ),
          #0b0d12;
        color: #c8ff3d;
        cursor: pointer;
        font-family: var(
          --ep-font-chrome,
          var(--font-mono, 'IBM Plex Mono', monospace)
        );
      }
      .glyph {
        width: 34px;
        height: 34px;
      }
      .scene-title {
        font-size: 10px;
        letter-spacing: 0.22em;
        text-transform: uppercase;
        color: #9aa48c;
        max-width: 90%;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .scene-err {
        font-size: 9px;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color: #e2604f;
      }
      [data-bg='paper'] {
        background: #f7f4ec;
      }
      [data-bg='paper'] .poster {
        background:
          radial-gradient(
            80% 70% at 50% 40%,
            rgba(195, 61, 46, 0.05),
            transparent 70%
          ),
          #f7f4ec;
        color: #c33d2e;
      }
      [data-bg='paper'] .scene-title {
        color: #6d6753;
      }
      [data-bg='paper'] .scene-stop {
        border-color: rgba(195, 61, 46, 0.5);
        background: rgba(247, 244, 236, 0.85);
        color: #c33d2e;
      }
      .scene-stop {
        position: absolute;
        top: 6px;
        right: 6px;
        width: 26px;
        height: 26px;
        border: 1px solid rgba(200, 255, 61, 0.4);
        border-radius: 50%;
        background: rgba(11, 13, 18, 0.8);
        color: #c8ff3d;
        font-size: 11px;
        cursor: pointer;
      }
    </style>
  </template>
}
