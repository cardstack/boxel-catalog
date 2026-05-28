import {
  surfaceElementForId,
  surfaceRuntimeForElement,
} from './dom-registry.ts';
import { isSurfaceTextEntryTarget } from './keyboard.ts';
import type { SurfaceRuntime } from './surface-runtime.ts';

export interface SurfaceCanvasDomOptions {
  root?: Document | HTMLElement | null;
  focusDom?: boolean;
  reveal?: boolean;
  restoreSource?: boolean;
}

export function restoreSurfaceCanvasSelection(
  id: string,
  options: SurfaceCanvasDomOptions = {},
): boolean {
  const target = surfaceCanvasElementForId(id, options.root);
  const runtime = target ? surfaceRuntimeForElement(target) : undefined;
  if (!target || !runtime) return false;

  runtime.select(id, { restoreSource: options.restoreSource ?? true });
  if (options.focusDom)
    focusSurfaceCanvasObject(target, options.reveal ?? false);
  return runtimeOwnsSelection(runtime, id);
}

export function clearSurfaceCanvasSelection(
  root: Document | HTMLElement | null | undefined,
): boolean {
  const rootElement = rootElementFor(root);
  const runtime = rootElement
    ? surfaceRuntimeForElement(rootElement)
    : undefined;
  if (!rootElement || !runtime) return false;
  rootElement.dataset['surfaceCanvasSelectionCleared'] = 'true';
  runtime.clearInteractionState();
  releaseSurfaceCanvasDomFocus(rootElement);
  return true;
}

export function releaseSurfaceCanvasDomFocus(
  root: Document | HTMLElement | null | undefined,
): boolean {
  const rootElement = rootElementFor(root);
  const active = rootElement?.ownerDocument.activeElement;
  if (!rootElement || !(active instanceof HTMLElement)) return false;
  if (!rootElement.contains(active)) return false;
  if (surfaceTargetRetainsFocus(active)) return false;

  const activeObject = active.closest<HTMLElement>(
    '[data-surface-component="frame"][data-canvas-object], [data-canvas-object], [data-surface-canvas-object]',
  );
  if (!activeObject || !rootElement.contains(activeObject)) return false;

  active.blur();
  return rootElement.ownerDocument.activeElement !== active;
}

function surfaceCanvasElementForId(
  id: string,
  root: Document | HTMLElement | null | undefined,
): HTMLElement | null {
  const rootElement = rootElementFor(root);
  if (!rootElement) return null;
  return (
    surfaceElementForId(rootElement, id) ??
    rootElement.ownerDocument.getElementById(id)
  );
}

function rootElementFor(
  root: Document | HTMLElement | null | undefined,
): HTMLElement | null {
  if (root && 'nodeType' in root && root.nodeType === 1) {
    return root as HTMLElement;
  }
  if (root && 'documentElement' in root) {
    return (
      root.querySelector('[data-surface-canvas-binding="active"]') ??
      root.documentElement
    );
  }
  if (typeof document !== 'undefined') {
    return (
      document.querySelector('[data-surface-canvas-binding="active"]') ??
      document.documentElement
    );
  }
  return null;
}

function focusSurfaceCanvasObject(object: HTMLElement, reveal: boolean): void {
  if (!surfaceTargetRetainsFocus(object.ownerDocument.activeElement)) {
    object.focus({ preventScroll: true });
  }
  if (reveal) {
    object.scrollIntoView({ block: 'nearest', inline: 'nearest' });
  }
}

function surfaceTargetRetainsFocus(target: Element | null): boolean {
  if (!target) return false;
  return (
    isSurfaceTextEntryTarget(target) ||
    target.closest('[data-surface-keyboard-owner], [data-bx-lift]') !== null
  );
}

function runtimeOwnsSelection(runtime: SurfaceRuntime, id: string): boolean {
  const snapshot = runtime.snapshot();
  if (snapshot.focusedId !== id) return false;
  return Object.values(snapshot.selections).some(
    (selection) =>
      selection.headId === id &&
      selection.ids.length === 1 &&
      selection.ids[0] === id,
  );
}
