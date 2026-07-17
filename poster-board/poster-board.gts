import {
  CardDef,
  Component,
  field,
  contains,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import { tracked } from '@glimmer/tracking';
import { htmlSafe } from '@ember/template';
import { on } from '@ember/modifier';
import Modifier from 'ember-modifier';
import LayoutDashboardIcon from '@cardstack/boxel-icons/layout-dashboard';
import { RigState, SurfaceRig, type PanSession } from './rig';

interface OnInsertSignature {
  Element: HTMLElement;
  Args: {
    Positional: [(el: HTMLElement) => void];
  };
}

class OnInsert extends Modifier<OnInsertSignature> {
  modify(el: HTMLElement, [callback]: [(el: HTMLElement) => void]) {
    callback(el);
  }
}

class Isolated extends Component<typeof PosterBoard> {
  rig = new RigState();
  surfaceRig = new SurfaceRig(this.rig);

  @tracked isPanning = false;
  private panSession: PanSession | null = null;
  private rootElement: HTMLElement | null = null;
  private keydownHandler: ((e: KeyboardEvent) => void) | null = null;

  get zoomLabel() {
    return Math.round(this.rig.magnify * 100) + '%';
  }

  get planeStyle() {
    const r = this.rig;
    return htmlSafe(
      `transform: scale(${r.magnify}) translate(${r.worldX}px, ${r.worldY}px); transform-origin: 0 0;`,
    );
  }

  get rootStyle() {
    return htmlSafe(`cursor: ${this.isPanning ? 'grabbing' : 'grab'};`);
  }

  // ── Wheel ──────────────────────────────────────────────

  handleWheel = (event: Event) => {
    this.surfaceRig.handleWheel(event as WheelEvent);
  };

  // ── Pointer pan ────────────────────────────────────────

  handlePointerDown = (rawEvent: Event) => {
    const event = rawEvent as PointerEvent;
    const target = event.target as HTMLElement;
    if (target.closest('[data-poster-board-hud]')) {
      return;
    }
    this.panSession = this.surfaceRig.startPan(event.clientX, event.clientY);
    this.isPanning = true;
    (event.currentTarget as HTMLElement).setPointerCapture(event.pointerId);
    event.preventDefault();
  };

  handlePointerMove = (rawEvent: Event) => {
    const event = rawEvent as PointerEvent;
    this.panSession?.move(event.clientX, event.clientY);
  };

  handlePointerUp = (rawEvent: Event) => {
    const event = rawEvent as PointerEvent;
    if (!this.panSession) {
      return;
    }
    this.panSession.end();
    this.panSession = null;
    this.isPanning = false;
    try {
      (event.currentTarget as HTMLElement).releasePointerCapture(
        event.pointerId,
      );
    } catch {
      // pointer capture may already be released (e.g. pointercancel)
    }
  };

  // ── Zoom controls ──────────────────────────────────────

  zoomIn = () => {
    this.surfaceRig.zoomCentered(1.2, this.rootElement);
  };

  zoomOut = () => {
    this.surfaceRig.zoomCentered(1 / 1.2, this.rootElement);
  };

  zoom100 = () => {
    this.surfaceRig.zoomCentered(1 / this.rig.magnify, this.rootElement);
  };

  resetView = () => {
    this.surfaceRig.stopAll();
    this.rig.worldX = 0;
    this.rig.worldY = 0;
    this.rig.magnify = 1;
  };

  handleKeyDown = (event: KeyboardEvent) => {
    const target = event.target as HTMLElement;
    if (
      target.tagName === 'INPUT' ||
      target.tagName === 'TEXTAREA' ||
      target.isContentEditable
    ) {
      return;
    }
    if (event.shiftKey && (event.key === '=' || event.key === '+')) {
      event.preventDefault();
      this.zoomIn();
    } else if (event.shiftKey && event.key === '-') {
      event.preventDefault();
      this.zoomOut();
    } else if (event.shiftKey && event.key === '0') {
      event.preventDefault();
      this.zoom100();
    }
  };

  // ── Lifecycle ──────────────────────────────────────────

  handleInserted = (el: HTMLElement) => {
    this.rootElement = el;
    this.keydownHandler = this.handleKeyDown;
    window.addEventListener('keydown', this.keydownHandler);
  };

  willDestroy(): void {
    if (this.keydownHandler) {
      window.removeEventListener('keydown', this.keydownHandler);
      this.keydownHandler = null;
    }
    this.surfaceRig.destroy();
    super.willDestroy();
  }

  <template>
    {{! template-lint-disable no-inline-styles no-pointer-down-event-binding }}
    <div
      class='poster-board-root'
      data-test-poster-board
      style={{this.rootStyle}}
      {{OnInsert this.handleInserted}}
      {{on 'wheel' this.handleWheel}}
      {{on 'pointerdown' this.handlePointerDown}}
      {{on 'pointermove' this.handlePointerMove}}
      {{on 'pointerup' this.handlePointerUp}}
      {{on 'pointercancel' this.handlePointerUp}}
    >
      <div class='poster-board-plane' style={{this.planeStyle}}>
        <div class='poster-board-grid' aria-hidden='true'></div>
        <div class='poster-board-hint'>
          <span class='poster-board-hint-title'>{{if
              @model.title
              @model.title
              'Untitled Poster Board'
            }}</span>
          <span class='poster-board-hint-line'>Scroll to pan · ⌘ or Ctrl +
            scroll to zoom · Drag to pan</span>
        </div>
      </div>

      <div
        class='poster-board-hud'
        data-poster-board-hud
        data-test-poster-board-hud
      >
        <button
          type='button'
          class='poster-board-hud-btn'
          data-test-zoom-in
          aria-label='Zoom in'
          {{on 'click' this.zoomIn}}
        >+</button>
        <span class='poster-board-hud-zoom' data-test-zoom-level>
          {{this.zoomLabel}}
        </span>
        <button
          type='button'
          class='poster-board-hud-btn'
          data-test-zoom-out
          aria-label='Zoom out'
          {{on 'click' this.zoomOut}}
        >−</button>
        <button
          type='button'
          class='poster-board-hud-btn poster-board-hud-btn-wide'
          data-test-zoom-reset
          {{on 'click' this.zoom100}}
        >100%</button>
        <button
          type='button'
          class='poster-board-hud-btn poster-board-hud-btn-wide'
          data-test-fit
          {{on 'click' this.resetView}}
        >Fit</button>
      </div>
    </div>

    <style scoped>
      .poster-board-root {
        position: relative;
        width: 100%;
        height: 100%;
        overflow: hidden;
        touch-action: none;
        min-width: 0;
        background: var(--background);
      }

      .poster-board-plane {
        will-change: transform;
      }

      .poster-board-grid {
        position: absolute;
        inset: -312.5rem;
        width: 625rem;
        height: 625rem;
        pointer-events: none;
        background-image: radial-gradient(
          circle,
          color-mix(in oklch, var(--muted-foreground) 35%, transparent) 1px,
          transparent 1px
        );
        background-size: 1.5rem 1.5rem;
      }

      .poster-board-hint {
        position: absolute;
        top: 2.5rem;
        left: 2.5rem;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-2xs);
        pointer-events: none;
        user-select: none;
      }

      .poster-board-hint-title {
        font: 600 var(--boxel-font-lg);
        color: var(--foreground);
      }

      .poster-board-hint-line {
        font: var(--boxel-font-sm);
        color: var(--muted-foreground);
      }

      .poster-board-hud {
        position: absolute;
        top: var(--boxel-sp-xs);
        right: var(--boxel-sp-xs);
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-4xs);
        padding: var(--boxel-sp-4xs) var(--boxel-sp-2xs);
        background: color-mix(in oklch, var(--card) 88%, transparent);
        border: 1px solid var(--border);
        border-radius: 0.5rem;
        backdrop-filter: blur(10px);
        -webkit-backdrop-filter: blur(10px);
        box-shadow: 0 0.125rem 0.5rem
          color-mix(in oklch, var(--foreground) 8%, transparent);
        z-index: 10;
        cursor: default;
      }

      .poster-board-hud-btn {
        width: 1.625rem;
        height: 1.625rem;
        border: none;
        border-radius: 0.3125rem;
        background: var(--muted);
        color: var(--foreground);
        font-size: 0.8125rem;
        font-weight: 700;
        cursor: pointer;
        display: grid;
        place-items: center;
        transition: background 0.12s;
      }

      .poster-board-hud-btn:hover {
        background: var(--border);
      }

      .poster-board-hud-btn-wide {
        width: auto;
        padding: 0 var(--boxel-sp-2xs);
        font-size: 0.625rem;
        font-weight: 600;
      }

      .poster-board-hud-zoom {
        min-width: 2.125rem;
        text-align: center;
        font-size: 0.625rem;
        font-weight: 600;
        font-variant-numeric: tabular-nums;
        color: var(--muted-foreground);
      }
    </style>
  </template>
}

export class PosterBoard extends CardDef {
  static displayName = 'Poster Board';
  static icon = LayoutDashboardIcon;
  static prefersWideFormat = true;

  @field title = contains(StringField);

  static isolated = Isolated;
}
