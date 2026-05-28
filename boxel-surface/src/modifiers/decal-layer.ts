import { modifier } from 'ember-modifier';

import type {
  FociDecalShape,
  FociMode,
  FociProjection,
  FociProjectionAdornment,
  FociProjectionDecal,
} from '../foci-store.ts';
import {
  SURFACE_LAYERS,
  clipSurfaceLayerRect,
  type SurfaceLayerBox,
  type SurfaceLayerClipBounds,
  type SurfaceLayerCornerRadii,
  type SurfaceLayerRect,
} from '../layer-manager.ts';
import {
  surfaceElementsForIds,
  surfaceRuntimeForElement,
} from '../dom-registry.ts';
import { SURFACE_GEOMETRY_CHANGE_EVENT } from '../geometry-events.ts';
import type { SurfaceRuntime } from '../surface-runtime.ts';
import type { SurfaceScopeRelay } from '../scope-relay.ts';

export type SurfaceDecalLayerClip = 'none' | 'viewport' | 'self';

export interface SurfaceDecalLayerOptions {
  active?: boolean;
  className?: string;
  clip?: SurfaceDecalLayerClip;
  mode?: FociMode;
  projection?: FociProjection;
  rootId?: string | null;
  runtime?: SurfaceRuntime;
  scopeRelay?: SurfaceScopeRelay;
  tolerance?: number;
  kinds?: readonly FociProjectionAdornment[];
}

interface ActiveLiftDecalState {
  lift: HTMLElement;
  anchor: HTMLElement | null;
  anchorDecal: boolean;
}

const StyleId = 'boxel-surface-decal-layer-styles';
const SVG_NS = 'http://www.w3.org/2000/svg';
const DEFAULT_DECAL_STROKE_WIDTH = 2;
const DECAL_ZOOM_VARIABLE = '--surface-decal-zoom';
const DECAL_STROKE_WIDTH_VARIABLE = '--surface-decal-stroke-width';

const KIND_CLASS: Partial<Record<FociProjectionAdornment, string>> = {
  receiver: 'drop-target',
};

const DECAL_THEME_VARIABLES = [
  '--boxel-highlight',
  '--boxel-orange',
  '--boxel-lilac',
  '--boxel-lilac-lift',
  '--surface-decal-highlight',
  '--surface-decal-transfer',
  '--surface-decal-inspect',
  '--surface-decal-context',
  '--surface-decal-active-edit-bg',
  '--surface-decal-highlight-fill',
  '--surface-decal-highlight-fill-soft',
  '--surface-decal-transfer-fill',
  '--surface-decal-transfer-fill-soft',
  '--surface-decal-inspect-fill',
  '--surface-decal-context-fill',
  '--surface-decal-hover-fill',
] as const;

function ensureStyles(document: Document): void {
  if (document.getElementById(StyleId)) return;

  const style = document.createElement('style');
  style.id = StyleId;
  style.textContent = `
    .bx-surface-decal-layer {
      position: fixed;
      inset: 0;
      pointer-events: none;
      contain: layout style;
      --surface-decal-stroke-width: 2px;
      --surface-decal-fine-stroke-width: max(1px, calc(var(--surface-decal-stroke-width) / 2));
      --surface-decal-halo-width: calc(var(--surface-decal-stroke-width) * 2);
      --surface-decal-inspect-halo-width: calc(var(--surface-decal-stroke-width) * 2.5);
    }

    .bx-surface-lift-decal-layer {
      position: fixed;
      inset: 0;
      pointer-events: none;
      contain: layout style;
      --surface-decal-stroke-width: 2px;
      --surface-decal-fine-stroke-width: max(1px, calc(var(--surface-decal-stroke-width) / 2));
      --surface-decal-halo-width: calc(var(--surface-decal-stroke-width) * 2);
      --surface-decal-inspect-halo-width: calc(var(--surface-decal-stroke-width) * 2.5);
    }

    .bx-surface-decal {
      position: fixed;
      box-sizing: border-box;
      pointer-events: none;
      border-radius: 2px;
      background: transparent;
    }

    .bx-surface-decal--focus,
    .bx-surface-decal--selection,
    .bx-surface-decal--lift-focus {
      border: var(--surface-decal-stroke-width) solid var(--surface-decal-highlight, #00ffba);
      box-shadow:
        0 0 0 var(--surface-decal-fine-stroke-width) color-mix(in srgb, var(--surface-decal-highlight, #00ffba) 22%, transparent),
        0 0 0 var(--surface-decal-halo-width) var(--surface-decal-highlight-fill, rgba(0, 255, 186, 0.18));
    }

    .bx-surface-decal--range {
      border: var(--surface-decal-stroke-width) solid var(--surface-decal-highlight, #00ffba);
      background: var(--surface-decal-highlight-fill-soft, rgba(0, 255, 186, 0.10));
      box-shadow:
        0 0 0 var(--surface-decal-fine-stroke-width) color-mix(in srgb, var(--surface-decal-highlight, #00ffba) 18%, transparent),
        0 0 0 var(--surface-decal-halo-width) var(--surface-decal-highlight-fill-soft, rgba(0, 255, 186, 0.10));
    }

    .bx-surface-decal--edit-anchor {
      border: var(--surface-decal-fine-stroke-width) solid color-mix(in srgb, var(--surface-decal-highlight, #00ffba) 32%, transparent);
      background: color-mix(in srgb, var(--surface-decal-highlight, #00ffba) 3%, transparent);
      box-shadow: 0 0 0 calc(var(--surface-decal-stroke-width) * 1.5) color-mix(in srgb, var(--surface-decal-highlight, #00ffba) 5%, transparent);
    }

    .bx-surface-decal--inspect {
      border: var(--surface-decal-stroke-width) solid var(--surface-decal-inspect, #a66dfa);
      box-shadow:
        0 0 0 var(--surface-decal-fine-stroke-width) color-mix(in srgb, var(--surface-decal-inspect, #a66dfa) 42%, transparent),
        0 0 0 var(--surface-decal-inspect-halo-width) var(--surface-decal-inspect-fill, rgba(166, 109, 250, 0.18)),
        0 0 18px color-mix(in srgb, var(--surface-decal-inspect, #a66dfa) 20%, transparent);
    }

    .bx-surface-decal--receiver,
    .bx-surface-decal--drop-target {
      border: var(--surface-decal-stroke-width) dashed var(--surface-decal-transfer, #ff7f00);
      background: var(--surface-decal-transfer-fill-soft, rgba(255, 127, 0, 0.08));
      box-shadow: 0 0 0 var(--surface-decal-halo-width) var(--surface-decal-transfer-fill, rgba(255, 127, 0, 0.16));
    }

    .bx-surface-decal--source,
    .bx-surface-decal--origin {
      border: var(--surface-decal-stroke-width) dashed var(--surface-decal-transfer, #ff7f00);
      background: var(--surface-decal-transfer-fill, rgba(255, 127, 0, 0.16));
      box-shadow: 0 0 0 calc(var(--surface-decal-stroke-width) * 1.5) var(--surface-decal-transfer-fill, rgba(255, 127, 0, 0.16));
    }

    .bx-surface-decal--destination {
      border: var(--surface-decal-stroke-width) solid var(--surface-decal-transfer, #ff7f00);
      background: var(--surface-decal-transfer-fill, rgba(255, 127, 0, 0.16));
      box-shadow: 0 0 0 var(--surface-decal-halo-width) var(--surface-decal-transfer-fill-soft, rgba(255, 127, 0, 0.08));
    }

    .bx-surface-decal--context,
    .bx-surface-decal--hover {
      border: var(--surface-decal-fine-stroke-width) solid color-mix(in srgb, var(--surface-decal-context, #919191) 22%, transparent);
      background: var(--surface-decal-context-fill, rgba(0, 0, 0, 0.04));
      opacity: 0.72;
    }

    .bx-surface-decal--hover {
      background: var(--surface-decal-hover-fill, rgba(0, 0, 0, 0.04));
    }

    .bx-surface-decal-path-svg {
      position: fixed;
      inset: 0;
      width: 100vw;
      height: 100vh;
      overflow: visible;
      pointer-events: none;
      contain: layout style;
    }

    .bx-surface-decal-path {
      fill: none;
      stroke: var(--surface-decal-highlight, #00ffba);
      stroke-width: var(--surface-decal-stroke-width);
      vector-effect: non-scaling-stroke;
      filter: drop-shadow(0 0 var(--surface-decal-halo-width) var(--surface-decal-highlight-fill, rgba(0, 255, 186, 0.18)));
    }

    .bx-surface-decal-path--inspect {
      stroke: var(--surface-decal-inspect, #a66dfa);
      filter: drop-shadow(0 0 var(--surface-decal-inspect-halo-width) var(--surface-decal-inspect-fill, rgba(166, 109, 250, 0.18)));
    }

    .bx-surface-decal-path--receiver,
    .bx-surface-decal-path--drop-target,
    .bx-surface-decal-path--source,
    .bx-surface-decal-path--origin,
    .bx-surface-decal-path--destination {
      stroke: var(--surface-decal-transfer, #ff7f00);
      stroke-dasharray: 6 4;
      filter: drop-shadow(0 0 var(--surface-decal-halo-width) var(--surface-decal-transfer-fill, rgba(255, 127, 0, 0.16)));
    }
  `;
  document.head.append(style);
}

function syncDecalThemeVariables(
  source: HTMLElement,
  target: HTMLElement,
): void {
  const styles = source.ownerDocument.defaultView?.getComputedStyle(source);
  if (!styles) return;
  for (const name of DECAL_THEME_VARIABLES) {
    const value = styles.getPropertyValue(name).trim();
    if (value) target.style.setProperty(name, value);
  }
}

function syncDecalStrokeWidth(
  source: HTMLElement,
  runtime: SurfaceRuntime | undefined,
  ...targets: HTMLElement[]
): void {
  const styles = source.ownerDocument.defaultView?.getComputedStyle(source);
  if (!styles) return;
  const explicitStroke = parsePositiveNumber(
    styles.getPropertyValue(DECAL_STROKE_WIDTH_VARIABLE),
  );
  const zoom =
    runtime?.viewport.zoom ??
    parsePositiveNumber(styles.getPropertyValue(DECAL_ZOOM_VARIABLE)) ??
    1;
  const strokeWidth =
    explicitStroke ?? Math.max(DEFAULT_DECAL_STROKE_WIDTH / zoom, 1);
  const rounded = Math.round(strokeWidth * 1000) / 1000;
  for (const target of targets) {
    target.style.setProperty(DECAL_STROKE_WIDTH_VARIABLE, `${rounded}px`);
  }
}

function parsePositiveNumber(value: string): number | null {
  const parsed = Number.parseFloat(value.trim());
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

function clipRectFor(
  document: Document,
  element: HTMLElement,
  clip: SurfaceDecalLayerClip,
): SurfaceLayerClipBounds | null {
  const view = document.defaultView ?? window;
  const viewport = new DOMRect(0, 0, view.innerWidth, view.innerHeight);
  if (clip === 'none') return null;
  if (clip === 'viewport') return viewport;
  return (
    intersectDomRects(viewport, element.getBoundingClientRect()) ?? viewport
  );
}

function intersectDomRects(
  a: SurfaceLayerClipBounds,
  b: SurfaceLayerClipBounds,
): DOMRect | null {
  const left = Math.max(a.left, b.left);
  const top = Math.max(a.top, b.top);
  const right = Math.min(a.right, b.right);
  const bottom = Math.min(a.bottom, b.bottom);
  if (right <= left || bottom <= top) return null;
  return new DOMRect(left, top, right - left, bottom - top);
}

function sourceRectForElement(element: HTMLElement): DOMRect | null {
  const elementRect = element.getBoundingClientRect();
  return elementRect.width > 0 && elementRect.height > 0
    ? elementRect
    : descendantFallbackRectForElement(element);
}

function radiusSourceForElement(element: HTMLElement): HTMLElement {
  const elementRect = element.getBoundingClientRect();
  if (elementRect.width > 0 && elementRect.height > 0) return element;

  if (!allowsDescendantRectFallback(element)) return element;
  let best: HTMLElement | null = null;
  let bestArea = 0;
  for (const descendant of element.querySelectorAll<HTMLElement>('*')) {
    const rect = descendant.getBoundingClientRect();
    const area = rect.width * rect.height;
    if (rect.width <= 0 || rect.height <= 0 || area <= bestArea) continue;
    best = descendant;
    bestArea = area;
  }
  return best ?? element;
}

function cornerRadiiForElement(
  element: HTMLElement,
  rect: DOMRect | SurfaceLayerRect | SurfaceLayerBox,
): SurfaceLayerCornerRadii | undefined {
  const styles = element.ownerDocument.defaultView?.getComputedStyle(element);
  if (!styles) return undefined;

  const width = rect.width;
  const height = rect.height;
  const max = Math.max(0, Math.min(width, height) / 2);
  return {
    topLeft: clampDecalRadius(
      parseRadius(styles.borderTopLeftRadius, width, height),
      max,
    ),
    topRight: clampDecalRadius(
      parseRadius(styles.borderTopRightRadius, width, height),
      max,
    ),
    bottomRight: clampDecalRadius(
      parseRadius(styles.borderBottomRightRadius, width, height),
      max,
    ),
    bottomLeft: clampDecalRadius(
      parseRadius(styles.borderBottomLeftRadius, width, height),
      max,
    ),
  };
}

function parseRadius(value: string, width: number, height: number): number {
  const token = value.trim().split(/\s+/)[0] ?? '';
  if (token.endsWith('px')) {
    const parsed = Number.parseFloat(token);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  if (token.endsWith('%')) {
    const parsed = Number.parseFloat(token);
    return Number.isFinite(parsed)
      ? Math.min(width, height) * (parsed / 100)
      : 0;
  }
  const parsed = Number.parseFloat(token);
  return Number.isFinite(parsed) ? parsed : 0;
}

function clampDecalRadius(value: number, max: number): number {
  if (!Number.isFinite(value)) return 0;
  return Math.max(0, Math.min(value, max));
}

function cornerRadiiCss(radius: SurfaceLayerCornerRadii | undefined): string {
  if (!radius) return '';
  return [
    radius.topLeft,
    radius.topRight,
    radius.bottomRight,
    radius.bottomLeft,
  ]
    .map((value) => `${Math.round(value * 100) / 100}px`)
    .join(' ');
}

function hasMeaningfulVisibleArea(
  clipped: SurfaceLayerRect,
  source: SurfaceLayerRect,
): boolean {
  const minWidth = Math.min(8, source.width);
  const minHeight = Math.min(8, source.height);
  return clipped.width >= minWidth && clipped.height >= minHeight;
}

function rectForElement(element: HTMLElement): SurfaceLayerRect | null {
  const sourceRect = sourceRectForElement(element);
  if (!sourceRect) return null;
  const radiusElement = radiusSourceForElement(element);

  return {
    id:
      element.getAttribute('data-ladder-id') ??
      element.dataset['bxGridTraversalId'] ??
      element.id,
    left: sourceRect.left,
    top: sourceRect.top,
    width: sourceRect.width,
    height: sourceRect.height,
    radius: cornerRadiiForElement(radiusElement, sourceRect),
  };
}

function decalShapeForTarget(element: HTMLElement): FociDecalShape {
  const explicit = element.getAttribute('data-surface-decal-shape');
  if (explicit === 'rect' || explicit === 'path' || explicit === 'none') {
    return explicit;
  }
  if (
    element.classList.contains('boxel-canvas__edge') ||
    element.getAttribute('data-surface-component') === 'edge' ||
    element.hasAttribute('data-surface-canvas-edge')
  ) {
    return 'path';
  }
  return 'rect';
}

function pathForElement(element: HTMLElement): SVGPathElement | null {
  if (element instanceof SVGPathElement) return element;
  return element.querySelector<SVGPathElement>(
    '[data-surface-decal-path], .boxel-canvas__edge-path, path:not(.boxel-canvas__edge-interaction)',
  );
}

function hiddenReasonForElement(
  element: HTMLElement,
  clip: SurfaceLayerClipBounds,
): 'missing-layout' | 'offscreen-or-clipped' | null {
  const sourceRect = sourceRectForElement(element);
  if (!sourceRect) return 'missing-layout';
  return intersectDomRects(sourceRect, clip) ? null : 'offscreen-or-clipped';
}

function descendantFallbackRectForElement(
  element: HTMLElement,
): DOMRect | null {
  if (!allowsDescendantRectFallback(element)) return null;
  return descendantUnionRect(element);
}

function allowsDescendantRectFallback(element: HTMLElement): boolean {
  const surface =
    element.getAttribute('data-surface') ??
    element.getAttribute('data-surface-component');
  return surface === 'cell' || surface === 'run' || surface === 'unit';
}

function descendantUnionRect(element: HTMLElement): DOMRect | null {
  let left = Number.POSITIVE_INFINITY;
  let top = Number.POSITIVE_INFINITY;
  let right = Number.NEGATIVE_INFINITY;
  let bottom = Number.NEGATIVE_INFINITY;
  let found = false;

  for (const descendant of element.querySelectorAll<HTMLElement>('*')) {
    const rect = descendant.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) continue;
    left = Math.min(left, rect.left);
    top = Math.min(top, rect.top);
    right = Math.max(right, rect.right);
    bottom = Math.max(bottom, rect.bottom);
    found = true;
  }

  return found ? new DOMRect(left, top, right - left, bottom - top) : null;
}

function parsePixelValue(value: string): number | null {
  const trimmed = value.trim();
  if (!trimmed.endsWith('px')) return null;
  const parsed = Number.parseFloat(trimmed);
  return Number.isFinite(parsed) ? parsed : null;
}

function rectForFixedLiftElement(
  element: HTMLElement,
  clip: SurfaceLayerClipBounds,
): SurfaceLayerRect | null {
  if (element.style.position !== 'fixed') return null;
  const left = parsePixelValue(element.style.left);
  const top = parsePixelValue(element.style.top);
  if (left === null || top === null) return null;

  const measured = element.getBoundingClientRect();
  const width = measured.width || element.offsetWidth;
  const height = measured.height || element.offsetHeight;
  if (width <= 0 || height <= 0) return null;

  const rect = intersectDomRects(new DOMRect(left, top, width, height), clip);
  if (!rect) return null;
  return {
    id:
      element.getAttribute('data-ladder-id') ??
      element.dataset['bxGridTraversalId'] ??
      element.id,
    left: rect.left,
    top: rect.top,
    width: rect.width,
    height: rect.height,
  };
}

function rectForLiftElement(
  element: HTMLElement,
  clip: SurfaceLayerClipBounds,
): SurfaceLayerRect | null {
  return rectForFixedLiftElement(element, clip) ?? rectForElement(element);
}

function topmostKeyboardLift(document: Document): HTMLElement | null {
  const lifts = Array.from(
    document.querySelectorAll<HTMLElement>(
      '[data-bx-lift][data-bx-lift-keyboard-lock="true"]',
    ),
  );
  return (
    lifts
      .filter((lift) => lift.isConnected)
      .sort((a, b) => {
        const za = Number(a.dataset['surfaceLayerZ'] ?? 0);
        const zb = Number(b.dataset['surfaceLayerZ'] ?? 0);
        return zb - za;
      })[0] ?? null
  );
}

function liftAnchorElement(lift: HTMLElement): HTMLElement | null {
  const selector = lift.getAttribute('data-bx-lift-anchor-selector');
  if (!selector) return null;
  try {
    return lift.ownerDocument.querySelector<HTMLElement>(selector);
  } catch {
    return null;
  }
}

function liftUsesShadowFocus(lift: HTMLElement): boolean {
  const kind = lift.getAttribute('data-bx-lift-kind');
  return kind === 'edit' || kind === 'tools';
}

function mutationInsideDecalLayer(
  target: Node,
  root: HTMLElement,
  liftRoot: HTMLElement,
): boolean {
  return (
    target === root ||
    target === liftRoot ||
    (target instanceof Node &&
      (root.contains(target) || liftRoot.contains(target)))
  );
}

function nodeContainsLift(node: Node): boolean {
  return (
    node instanceof HTMLElement &&
    (node.matches('[data-bx-lift]') ||
      node.querySelector('[data-bx-lift]') !== null)
  );
}

function mutationAffectsLiftLayer(
  mutation: MutationRecord,
  root: HTMLElement,
  liftRoot: HTMLElement,
): boolean {
  if (mutationInsideDecalLayer(mutation.target, root, liftRoot)) {
    return false;
  }

  if (mutation.type === 'attributes') {
    return (
      mutation.target instanceof HTMLElement &&
      (mutation.target.matches('[data-bx-lift]') ||
        mutation.target.closest('[data-bx-lift]') !== null)
    );
  }

  for (const node of [
    ...Array.from(mutation.addedNodes),
    ...Array.from(mutation.removedNodes),
  ]) {
    if (nodeContainsLift(node)) return true;
  }

  return false;
}

function renderLiftFocusDecal(
  document: Document,
  root: HTMLElement,
): ActiveLiftDecalState | null {
  root.replaceChildren();
  const lift = topmostKeyboardLift(document);
  if (!lift) {
    root.style.zIndex = '';
    return null;
  }
  if (liftUsesShadowFocus(lift)) {
    root.style.zIndex = '';
    return {
      lift,
      anchor: liftAnchorElement(lift),
      anchorDecal: true,
    };
  }
  const clip = clipRectFor(document, lift, 'viewport')!;
  const rect = rectForLiftElement(lift, clip);
  if (!rect) {
    root.style.zIndex = '';
    return { lift, anchor: liftAnchorElement(lift), anchorDecal: true };
  }

  const liftZ = Number(lift.dataset['surfaceLayerZ'] ?? 0);
  if (Number.isFinite(liftZ) && liftZ > 0) {
    root.style.zIndex = String(liftZ + 1);
  }

  const decal = document.createElement('div');
  decal.className = 'bx-surface-decal bx-surface-decal--lift-focus';
  decal.dataset['surfaceDecalKind'] = 'lift-focus';
  decal.dataset['surfaceDecalIds'] =
    lift.getAttribute('id') ??
    lift.getAttribute('data-bx-lift-focus-token') ??
    'active-lift';
  decal.style.left = `${rect.left}px`;
  decal.style.top = `${rect.top}px`;
  decal.style.width = `${rect.width}px`;
  decal.style.height = `${rect.height}px`;
  decal.style.borderRadius =
    cornerRadiiCss(cornerRadiiForElement(lift, rect)) ||
    getComputedStyle(lift).borderRadius ||
    '10px';
  root.append(decal);
  return { lift, anchor: liftAnchorElement(lift), anchorDecal: true };
}

function renderLiftAnchorDecal(
  document: Document,
  root: HTMLElement,
  state: ActiveLiftDecalState | null,
): void {
  if (!state?.anchor || !state.anchorDecal) return;
  const rect = rectForElement(state.anchor);
  if (!rect) return;

  const decal = document.createElement('div');
  decal.className = 'bx-surface-decal bx-surface-decal--edit-anchor';
  decal.dataset['surfaceDecalKind'] = 'edit-anchor';
  decal.dataset['surfaceDecalLiftAnchor'] = 'true';
  decal.dataset['surfaceDecalIds'] =
    state.anchor.getAttribute('data-ladder-id') ??
    state.anchor.dataset['bxGridTraversalId'] ??
    state.anchor.id ??
    'lift-anchor';
  decal.style.left = `${rect.left}px`;
  decal.style.top = `${rect.top}px`;
  decal.style.width = `${rect.width}px`;
  decal.style.height = `${rect.height}px`;
  decal.style.borderRadius = cornerRadiiCss(rect.radius);
  root.append(decal);
}

function decalCompetesWithLiftAnchor(
  kind: FociProjectionAdornment,
  targets: readonly HTMLElement[],
  state: ActiveLiftDecalState | null,
): boolean {
  if (!state?.anchor) return false;
  if (
    kind !== 'focus' &&
    kind !== 'selection' &&
    kind !== 'source' &&
    kind !== 'range'
  ) {
    return false;
  }
  return targets.includes(state.anchor);
}

function modeFor(
  element: HTMLElement,
  options: SurfaceDecalLayerOptions,
): FociMode {
  if (options.mode) return options.mode;
  const raw = element.closest<HTMLElement>('[data-surface-mode]')?.dataset[
    'surfaceMode'
  ];
  if (
    raw === 'use' ||
    raw === 'change' ||
    raw === 'inspect' ||
    raw === 'debug'
  ) {
    return raw;
  }
  return 'use';
}

function decalsFor(
  element: HTMLElement,
  options: SurfaceDecalLayerOptions,
): readonly FociProjectionDecal[] {
  if (options.projection) return options.projection.visualDecals;
  const runtime = options.runtime ?? surfaceRuntimeForElement(element);
  return (
    runtime?.projection(projectionOptionsFor(element, options)).visualDecals ??
    []
  );
}

function projectionOptionsFor(
  element: HTMLElement,
  options: SurfaceDecalLayerOptions,
): { mode: FociMode; rootId?: string | null } {
  const projectionOptions: { mode: FociMode; rootId?: string | null } = {
    mode: modeFor(element, options),
  };
  if (options.rootId !== undefined) {
    projectionOptions.rootId = options.rootId;
  }
  return projectionOptions;
}

function classForKind(kind: FociProjectionAdornment): string {
  return KIND_CLASS[kind] ?? kind;
}

const surfaceDecalLayer = modifier<{
  Element: HTMLElement;
  Args: {
    Positional: [];
    Named: SurfaceDecalLayerOptions;
  };
}>((element, _positional, options) => {
  const document = element.ownerDocument;
  const view = document.defaultView ?? window;
  ensureStyles(document);

  const root = document.createElement('div');
  const liftRoot = document.createElement('div');
  const z = SURFACE_LAYERS.allocate('selection');
  root.className = 'bx-surface-decal-layer';
  root.dataset['surfaceLayerTier'] = 'selection';
  root.dataset['surfaceLayerZ'] = String(z);
  root.style.zIndex = String(z);
  options.scopeRelay?.stamp(root);
  document.body.append(root);
  liftRoot.className = 'bx-surface-lift-decal-layer';
  liftRoot.dataset['surfaceLayerTier'] = 'lift-focus';
  options.scopeRelay?.stamp(liftRoot);
  document.body.append(liftRoot);

  let frame = 0;
  let retryCount = 0;
  let subscribedRuntime = options.runtime ?? surfaceRuntimeForElement(element);
  let unsubscribeRuntimeSelection: (() => void) | undefined;
  let unsubscribeRuntimeViewport: (() => void) | undefined;
  const renderedDecals = new Map<string, Element>();

  const removeLiftAnchorDecals = (): void => {
    for (const decal of root.querySelectorAll<HTMLElement>(
      '[data-surface-decal-lift-anchor="true"]',
    )) {
      decal.remove();
    }
  };

  const clearRootDecals = (): void => {
    for (const decal of renderedDecals.values()) {
      decal.remove();
    }
    renderedDecals.clear();
    removeLiftAnchorDecals();
  };

  const upsertRectDecal = (
    key: string,
    decalModel: FociProjectionDecal,
    box: SurfaceLayerBox,
  ): void => {
    const existing = renderedDecals.get(key);
    if (existing && !(existing instanceof HTMLElement)) {
      existing.remove();
      renderedDecals.delete(key);
    }
    let decal = renderedDecals.get(key) as HTMLElement | undefined;
    if (!decal) {
      decal = document.createElement('div');
      renderedDecals.set(key, decal);
      root.append(decal);
    }

    const kindClass = classForKind(decalModel.kind);
    decal.className = [
      'bx-surface-decal',
      `bx-surface-decal--${decalModel.kind}`,
      kindClass !== decalModel.kind ? `bx-surface-decal--${kindClass}` : '',
      options.className ?? '',
    ]
      .filter(Boolean)
      .join(' ');
    decal.dataset['surfaceDecalKey'] = key;
    decal.dataset['surfaceDecalKind'] = decalModel.kind;
    decal.dataset['surfaceDecalIds'] = box.ids.join(' ');
    decal.style.left = `${box.left}px`;
    decal.style.top = `${box.top}px`;
    decal.style.width = `${box.width}px`;
    decal.style.height = `${box.height}px`;
    decal.style.borderRadius = cornerRadiiCss(box.radius);
  };

  const upsertPathDecal = (
    key: string,
    decalModel: FociProjectionDecal,
    target: HTMLElement,
  ): boolean => {
    const sourcePath = pathForElement(target);
    const matrix = sourcePath?.getScreenCTM();
    const d = sourcePath?.getAttribute('d');
    if (!sourcePath || !matrix || !d) return false;

    const existing = renderedDecals.get(key);
    if (existing && !(existing instanceof SVGSVGElement)) {
      existing.remove();
      renderedDecals.delete(key);
    }
    let svg = renderedDecals.get(key) as SVGSVGElement | undefined;
    if (!svg) {
      svg = document.createElementNS(SVG_NS, 'svg');
      renderedDecals.set(key, svg);
      root.append(svg);
    }

    const kindClass = classForKind(decalModel.kind);
    svg.setAttribute(
      'class',
      ['bx-surface-decal-path-svg', options.className ?? '']
        .filter(Boolean)
        .join(' '),
    );
    svg.setAttribute('aria-hidden', 'true');
    svg.dataset['surfaceDecalKey'] = key;
    svg.dataset['surfaceDecalKind'] = decalModel.kind;
    svg.dataset['surfaceDecalIds'] = decalModel.ids.join(' ');
    svg.replaceChildren();

    const path = document.createElementNS(SVG_NS, 'path');
    path.setAttribute(
      'class',
      [
        'bx-surface-decal-path',
        `bx-surface-decal-path--${decalModel.kind}`,
        kindClass !== decalModel.kind
          ? `bx-surface-decal-path--${kindClass}`
          : '',
      ]
        .filter(Boolean)
        .join(' '),
    );
    path.setAttribute('d', d);
    path.setAttribute(
      'transform',
      `matrix(${matrix.a} ${matrix.b} ${matrix.c} ${matrix.d} ${matrix.e} ${matrix.f})`,
    );
    svg.append(path);
    return true;
  };

  const removeStaleDecals = (nextKeys: Set<string>): void => {
    for (const [key, decal] of renderedDecals) {
      if (nextKeys.has(key)) continue;
      decal.remove();
      renderedDecals.delete(key);
    }
  };

  const syncSubscriptions = (): SurfaceRuntime | undefined => {
    const nextRuntime = options.runtime ?? surfaceRuntimeForElement(element);

    if (nextRuntime !== subscribedRuntime) {
      unsubscribeRuntimeSelection?.();
      unsubscribeRuntimeViewport?.();
      unsubscribeRuntimeSelection = undefined;
      unsubscribeRuntimeViewport = undefined;
      subscribedRuntime = nextRuntime;
      unsubscribeRuntimeSelection =
        subscribedRuntime?.subscribeSelection(schedule);
      unsubscribeRuntimeViewport =
        subscribedRuntime?.subscribeViewport(schedule);
    }

    return subscribedRuntime;
  };

  const render = (): void => {
    frame = 0;
    options.scopeRelay?.stamp(root);
    options.scopeRelay?.stamp(liftRoot);
    syncDecalThemeVariables(element, root);
    syncDecalThemeVariables(element, liftRoot);
    root.dataset['surfaceDecalActive'] = String(options.active !== false);
    if (options.active === false) {
      clearRootDecals();
      liftRoot.replaceChildren();
      liftRoot.style.zIndex = '';
      return;
    }
    removeLiftAnchorDecals();
    const activeLift = renderLiftFocusDecal(document, liftRoot);
    renderLiftAnchorDecal(document, root, activeLift);

    const runtime = syncSubscriptions();
    syncDecalStrokeWidth(element, runtime, root, liftRoot);
    const clip = clipRectFor(document, element, options.clip ?? 'none');
    const diagnosticClip = clip ?? clipRectFor(document, element, 'viewport');
    const kindFilter = options.kinds ? new Set(options.kinds) : null;
    const decals = decalsFor(element, options);
    let targetCount = 0;
    let measuredTargetCount = 0;
    let hiddenTargetCount = 0;
    let boxCount = 0;
    root.dataset['surfaceDecalModelCount'] = String(decals.length);
    root.dataset['surfaceDecalRuntime'] = runtime ? 'ready' : 'missing';
    delete root.dataset['surfaceDecalFirstTargetRect'];
    delete root.dataset['surfaceDecalFirstHiddenReason'];

    if (!runtime && retryCount < 30) {
      retryCount += 1;
      schedule();
      return;
    }
    retryCount = 0;

    const nextDecalKeys = new Set<string>();
    const kindIndexes = new Map<FociProjectionAdornment, number>();

    for (const decalModel of decals) {
      if (kindFilter && !kindFilter.has(decalModel.kind)) continue;
      const targets = surfaceElementsForIds(element, decalModel.ids, runtime);
      if (decalCompetesWithLiftAnchor(decalModel.kind, targets, activeLift)) {
        continue;
      }
      targetCount += targets.length;
      const firstTarget = targets[0];
      if (
        firstTarget &&
        root.dataset['surfaceDecalFirstTargetRect'] === undefined
      ) {
        const rect = firstTarget.getBoundingClientRect();
        root.dataset['surfaceDecalFirstTargetRect'] = [
          Math.round(rect.left),
          Math.round(rect.top),
          Math.round(rect.width),
          Math.round(rect.height),
        ].join(' ');
      }
      const rects: SurfaceLayerRect[] = [];
      let pathCount = 0;
      for (const target of targets) {
        const shape = decalShapeForTarget(target);
        if (shape === 'none') {
          continue;
        }
        if (shape === 'path') {
          const key = `${decalModel.kind}:path:${pathCount}`;
          if (upsertPathDecal(key, decalModel, target)) {
            nextDecalKeys.add(key);
            pathCount += 1;
            measuredTargetCount += 1;
            continue;
          }
        }
        const rect = rectForElement(target);
        if (rect) {
          measuredTargetCount += 1;
          const visibleRect = clip ? clipSurfaceLayerRect(rect, clip) : rect;
          if (visibleRect && hasMeaningfulVisibleArea(visibleRect, rect)) {
            rects.push(visibleRect);
            continue;
          }
          hiddenTargetCount += 1;
          root.dataset['surfaceDecalFirstHiddenReason'] ??= diagnosticClip
            ? (hiddenReasonForElement(target, diagnosticClip) ??
              'offscreen-or-clipped')
            : 'offscreen-or-clipped';
          continue;
        }
        hiddenTargetCount += 1;
        root.dataset['surfaceDecalFirstHiddenReason'] ??= diagnosticClip
          ? (hiddenReasonForElement(target, diagnosticClip) ?? 'unknown')
          : 'unknown';
      }
      const boxes = SURFACE_LAYERS.collapseSelectionBoxes(rects, {
        tolerance: options.tolerance,
      });
      boxCount += boxes.length;

      for (const box of boxes) {
        const index = kindIndexes.get(decalModel.kind) ?? 0;
        kindIndexes.set(decalModel.kind, index + 1);
        const key = `${decalModel.kind}:${index}`;
        nextDecalKeys.add(key);
        upsertRectDecal(key, decalModel, box);
      }
    }
    removeStaleDecals(nextDecalKeys);
    root.dataset['surfaceDecalTargetCount'] = String(targetCount);
    root.dataset['surfaceDecalMeasuredTargetCount'] =
      String(measuredTargetCount);
    root.dataset['surfaceDecalHiddenTargetCount'] = String(hiddenTargetCount);
    root.dataset['surfaceDecalBoxCount'] = String(boxCount);
  };

  const schedule = (): void => {
    if (frame !== 0) return;
    frame = view.requestAnimationFrame(render);
  };

  unsubscribeRuntimeSelection = subscribedRuntime?.subscribeSelection(schedule);
  unsubscribeRuntimeViewport = subscribedRuntime?.subscribeViewport(schedule);

  schedule();
  element.addEventListener(SURFACE_GEOMETRY_CHANGE_EVENT, schedule);
  view.addEventListener('scroll', schedule, true);
  view.addEventListener('resize', schedule);
  const liftObserver = new MutationObserver((mutations) => {
    if (
      mutations.some((mutation) =>
        mutationAffectsLiftLayer(mutation, root, liftRoot),
      )
    ) {
      schedule();
    }
  });
  liftObserver.observe(document.body, {
    attributes: true,
    attributeFilter: [
      'data-bx-lift',
      'data-bx-lift-keyboard-lock',
      'data-surface-layer-z',
      'data-bx-lift-anchor-selector',
    ],
    childList: true,
    subtree: true,
  });

  return () => {
    if (frame !== 0) view.cancelAnimationFrame(frame);
    unsubscribeRuntimeSelection?.();
    unsubscribeRuntimeViewport?.();
    liftObserver.disconnect();
    element.removeEventListener(SURFACE_GEOMETRY_CHANGE_EVENT, schedule);
    view.removeEventListener('scroll', schedule, true);
    view.removeEventListener('resize', schedule);
    clearRootDecals();
    root.remove();
    liftRoot.remove();
    SURFACE_LAYERS.release(z);
  };
});

export default surfaceDecalLayer;
