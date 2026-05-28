import { modifier } from 'ember-modifier';

import { SURFACE_LAYERS, type SurfaceLayerRect } from '../layer-manager.ts';

export interface SurfaceSelectionDecalOptions {
  active?: boolean;
  className?: string;
  clipTo?: string;
  tolerance?: number;
  variant?: 'selection' | 'range';
}

const StyleId = 'boxel-surface-selection-decals-styles';

const DECAL_THEME_VARIABLES = [
  '--boxel-highlight',
  '--surface-decal-highlight',
  '--surface-decal-highlight-fill',
  '--surface-decal-highlight-fill-soft',
] as const;

function ensureStyles(document: Document): void {
  if (document.getElementById(StyleId)) return;

  const style = document.createElement('style');
  style.id = StyleId;
  style.textContent = `
    .bx-surface-selection-decal-layer {
      position: fixed;
      inset: 0;
      pointer-events: none;
      contain: layout style;
    }

    .bx-surface-selection-decal {
      position: fixed;
      box-sizing: border-box;
      pointer-events: none;
      border: 2px solid var(--surface-decal-highlight, #00ffba);
      border-radius: 2px;
      background: transparent;
      box-shadow:
        0 0 0 1px color-mix(in srgb, var(--surface-decal-highlight, #00ffba) 22%, transparent),
        0 0 0 4px var(--surface-decal-highlight-fill, rgba(0, 255, 186, 0.18));
    }

    .bx-surface-selection-decal--range {
      background: var(--surface-decal-highlight-fill-soft, rgba(0, 255, 186, 0.10));
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

function targetSelectors(
  targets: string | readonly string[] | null | undefined,
): string[] {
  if (!targets) return [];
  if (typeof targets === 'string') return targets ? [targets] : [];
  return targets.filter((target) => target.length > 0);
}

function clipRectFor(
  document: Document,
  element: HTMLElement,
  selector: string | undefined,
): DOMRect {
  const view = document.defaultView ?? window;
  const viewport = new DOMRect(0, 0, view.innerWidth, view.innerHeight);
  if (!selector) return viewport;
  const clip =
    element.closest<HTMLElement>(selector) ??
    document.querySelector<HTMLElement>(selector);
  if (!clip) return viewport;
  return intersectDomRects(viewport, clip.getBoundingClientRect()) ?? viewport;
}

function intersectDomRects(a: DOMRect, b: DOMRect): DOMRect | null {
  const left = Math.max(a.left, b.left);
  const top = Math.max(a.top, b.top);
  const right = Math.min(a.right, b.right);
  const bottom = Math.min(a.bottom, b.bottom);
  if (right <= left || bottom <= top) return null;
  return new DOMRect(left, top, right - left, bottom - top);
}

function rectForElement(
  element: HTMLElement,
  clip: DOMRect,
): SurfaceLayerRect | null {
  const rect = intersectDomRects(element.getBoundingClientRect(), clip);
  if (!rect) return null;
  return {
    id: element.id || element.dataset['surfaceId'],
    left: rect.left,
    top: rect.top,
    width: rect.width,
    height: rect.height,
  };
}

const surfaceSelectionDecals = modifier(
  (
    element: HTMLElement,
    [targets]: [string | readonly string[] | null | undefined],
    options: SurfaceSelectionDecalOptions,
  ) => {
    const document = element.ownerDocument;
    const view = document.defaultView ?? window;
    ensureStyles(document);

    const root = document.createElement('div');
    const z = SURFACE_LAYERS.allocate('selection');
    root.className = 'bx-surface-selection-decal-layer';
    root.dataset['surfaceLayerTier'] = 'selection';
    root.dataset['surfaceLayerZ'] = String(z);
    root.style.zIndex = String(z);
    document.body.append(root);

    let frame = 0;
    const render = (): void => {
      frame = 0;
      syncDecalThemeVariables(element, root);
      root.replaceChildren();

      if (options.active === false) return;

      const clip = clipRectFor(document, element, options.clipTo);
      const rects = targetSelectors(targets)
        .map((selector) => document.querySelector<HTMLElement>(selector))
        .filter((target): target is HTMLElement => target !== null)
        .map((target) => rectForElement(target, clip))
        .filter((rect): rect is SurfaceLayerRect => rect !== null);

      const boxes = SURFACE_LAYERS.collapseSelectionBoxes(rects, {
        tolerance: options.tolerance,
      });
      const variant = options.variant ?? 'selection';

      for (const box of boxes) {
        const decal = document.createElement('div');
        decal.className = [
          'bx-surface-selection-decal',
          `bx-surface-selection-decal--${variant}`,
          options.className ?? '',
        ]
          .filter(Boolean)
          .join(' ');
        decal.dataset['surfaceSelectionIds'] = box.ids.join(' ');
        decal.style.left = `${box.left}px`;
        decal.style.top = `${box.top}px`;
        decal.style.width = `${box.width}px`;
        decal.style.height = `${box.height}px`;
        root.append(decal);
      }
    };

    const schedule = (): void => {
      if (frame !== 0) return;
      frame = view.requestAnimationFrame(render);
    };

    schedule();
    view.addEventListener('scroll', schedule, true);
    view.addEventListener('resize', schedule);

    return () => {
      if (frame !== 0) view.cancelAnimationFrame(frame);
      view.removeEventListener('scroll', schedule, true);
      view.removeEventListener('resize', schedule);
      root.remove();
      SURFACE_LAYERS.release(z);
    };
  },
);

export default surfaceSelectionDecals;
