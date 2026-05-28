import {
  surfaceElementForId,
  surfaceRuntimeForElement,
} from './dom-registry.ts';
import type { FociCancelTrigger, FociCommitTrigger } from './foci-store.ts';
import { isSurfaceTextEntryTarget } from './keyboard.ts';
import type { SurfaceRuntime } from './surface-runtime.ts';

export interface SurfaceGridDomOptions {
  root?: Document | HTMLElement | null;
  focusDom?: boolean;
  reveal?: boolean;
  restoreSource?: boolean;
}

export interface SurfaceGridCommitOptions extends SurfaceGridDomOptions {
  trigger?: FociCommitTrigger;
  advance?: 'none' | 'up' | 'down';
}

export interface SurfaceGridCancelOptions extends SurfaceGridDomOptions {
  trigger?: FociCancelTrigger;
}

export function restoreSurfaceGridSelection(
  id: string,
  options: SurfaceGridDomOptions = {},
): boolean {
  const target = surfaceGridElementForId(id, options.root);
  const runtime = target ? surfaceRuntimeForElement(target) : undefined;
  if (!target || !runtime) return false;

  runtime.select(id, { restoreSource: options.restoreSource ?? true });
  if (options.focusDom) focusSurfaceGridCell(target, options.reveal ?? false);
  return runtimeOwnsSelection(runtime, id);
}

export function commitSurfaceGridInput(
  sourceId: string,
  options: SurfaceGridCommitOptions = {},
): boolean {
  const target = surfaceGridElementForId(sourceId, options.root);
  const runtime = target ? surfaceRuntimeForElement(target) : undefined;
  if (!target || !runtime) return false;

  const input = runtime.snapshot().input;
  if (
    input &&
    (input.sourceId === sourceId ||
      input.targetId === sourceId ||
      input.liftedTargetId === sourceId)
  ) {
    runtime.dispatch({
      type: 'commitInput',
      trigger: options.trigger ?? 'explicit',
      advance: options.advance ?? 'none',
      restoreSource: options.restoreSource ?? true,
    });
  }

  return restoreSurfaceGridSelection(sourceId, {
    ...options,
    restoreSource: true,
  });
}

export function cancelSurfaceGridInput(
  sourceId: string,
  options: SurfaceGridCancelOptions = {},
): boolean {
  const target = surfaceGridElementForId(sourceId, options.root);
  const runtime = target ? surfaceRuntimeForElement(target) : undefined;
  if (!target || !runtime) return false;

  const input = runtime.snapshot().input;
  if (
    input &&
    (input.sourceId === sourceId ||
      input.targetId === sourceId ||
      input.liftedTargetId === sourceId)
  ) {
    runtime.cancel(options.trigger ?? 'programmatic', {
      restoreSource: options.restoreSource ?? true,
    });
  }

  return restoreSurfaceGridSelection(sourceId, {
    ...options,
    restoreSource: true,
  });
}

export function clearSurfaceGridSelection(
  root: Document | HTMLElement | null | undefined,
): boolean {
  const rootElement = rootElementFor(root);
  const runtime = rootElement
    ? surfaceRuntimeForElement(rootElement)
    : undefined;
  if (!rootElement || !runtime) return false;
  rootElement.dataset['surfaceGridSelectionCleared'] = 'true';
  runtime.clearInteractionState();
  releaseSurfaceGridDomFocus(rootElement);
  return true;
}

export function releaseSurfaceGridDomFocus(
  root: Document | HTMLElement | null | undefined,
): boolean {
  const rootElement = rootElementFor(root);
  const active = rootElement?.ownerDocument.activeElement;
  if (!rootElement || !(active instanceof HTMLElement)) return false;
  if (!rootElement.contains(active)) return false;

  const activeGridCell = active.closest<HTMLElement>(
    '[data-surface-component="cell"][role="gridcell"], [role="gridcell"]',
  );
  if (!activeGridCell || !rootElement.contains(activeGridCell)) return false;
  if (surfaceTargetRetainsFocus(active, activeGridCell)) return false;

  active.blur();
  return rootElement.ownerDocument.activeElement !== active;
}

function surfaceGridElementForId(
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
      root.querySelector('[data-surface-grid-binding="active"]') ??
      root.documentElement
    );
  }
  if (typeof document !== 'undefined') {
    return (
      document.querySelector('[data-surface-grid-binding="active"]') ??
      document.documentElement
    );
  }
  return null;
}

function focusSurfaceGridCell(cell: HTMLElement, reveal: boolean): void {
  if (!surfaceTargetRetainsFocus(cell.ownerDocument.activeElement, cell)) {
    cell.focus({ preventScroll: true });
  }
  if (reveal) {
    cell.scrollIntoView({ block: 'nearest', inline: 'nearest' });
  }
}

function surfaceTargetRetainsFocus(
  target: Element | null,
  selectedCell?: HTMLElement,
): boolean {
  if (!target) return false;
  if (selectedCell?.contains(target) && isSurfaceTextEntryTarget(target)) {
    return true;
  }
  const lift = target.closest('[data-bx-lift]');
  if (lift) return true;
  const keyboardOwner = target.closest('[data-surface-keyboard-owner]');
  return Boolean(keyboardOwner && selectedCell?.contains(keyboardOwner));
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
