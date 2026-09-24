import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { modifier } from 'ember-modifier';

import PlayIcon from '@cardstack/boxel-icons/play';
import XIcon from '@cardstack/boxel-icons/x';
import { IconButton } from '@cardstack/boxel-ui/components';
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
        <IconButton
          @icon={{XIcon}}
          @variant='text-only'
          class='scene-stop'
          aria-label='Close animation'
          {{on 'click' this.stop}}
          {{on 'pointerdown' this.stopEvent}}
        />
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
        /* Two skins. Paper mode blends with the whiteboard's own theme. Screen
           mode is a projector — an intrinsically dark object — so it takes the
           contract's inverted pair (--tooltip / --tooltip-foreground) and both
           of its colours come from that one pair, which is what keeps them from
           disagreeing under any theme. Only the manim scene CONSTANTS in JS stay
           literal: they feed a runtime that cannot read var(). */
        --paper: var(--background);
        --echo: var(--chart-1);
        --chrome-soft: var(--muted-foreground);
        position: relative;
        width: 100%;
        height: 100%;
        min-height: 11.25rem;
        background-color: var(--tooltip);
        color: var(--tooltip-foreground);
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
        gap: 0.625rem;
        width: 100%;
        height: 100%;
        min-height: inherit;
        border: none;
        background:
          radial-gradient(
            80% 70% at 50% 40%,
            color-mix(in oklch, var(--tooltip-foreground) 6%, transparent),
            transparent 70%
          ),
          var(--tooltip);
        color: var(--tooltip-foreground);
        cursor: pointer;
        font-family: var(--font-mono);
      }
      .glyph {
        width: 2.125rem;
        height: 2.125rem;
      }
      .scene-title {
        font-size: 0.625rem;
        letter-spacing: 0.22em;
        text-transform: uppercase;
        color: color-mix(in oklch, var(--tooltip-foreground) 70%, transparent);
        max-width: 90%;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .scene-err {
        font-size: 0.5625rem;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color: var(--destructive-ink);
      }
      [data-bg='paper'] {
        background-color: var(--paper);
      }
      [data-bg='paper'] .poster {
        background:
          radial-gradient(
            80% 70% at 50% 40%,
            color-mix(in oklch, var(--echo) 5%, transparent),
            transparent 70%
          ),
          var(--paper);
        color: var(--echo);
      }
      [data-bg='paper'] .scene-title {
        color: var(--chrome-soft);
      }
      [data-bg='paper'] .scene-stop {
        border-color: color-mix(in oklch, var(--echo) 50%, transparent);
        background-color: color-mix(in oklch, var(--paper) 85%, transparent);
        color: var(--echo);
      }
      .echo-scene .scene-stop {
        position: absolute;
        top: 0.375rem;
        right: 0.375rem;
        width: 1.625rem;
        height: 1.625rem;
        border: 1px solid
          color-mix(in oklch, var(--tooltip-foreground) 40%, transparent);
        border-radius: 50%;
        background-color: color-mix(in oklch, var(--tooltip) 80%, transparent);
        color: var(--tooltip-foreground);
        font-size: 0.6875rem;
        cursor: pointer;
      }
    </style>
  </template>
}
