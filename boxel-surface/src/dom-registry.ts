import type { FocusLadder } from './focus-ladder.ts';
import type { LiftManager } from './lift-edges.ts';
import type { SurfaceRuntime } from './surface-runtime.ts';

const roots = new WeakMap<HTMLElement, FocusLadder>();
const runtimeRoots = new WeakMap<HTMLElement, SurfaceRuntime>();
const liftRoots = new WeakMap<HTMLElement, LiftManager>();
const surfaceElements = new WeakMap<
  SurfaceRuntime,
  Map<string, Set<HTMLElement>>
>();

export function registerSurfaceDomRoot(
  element: HTMLElement,
  ladder: FocusLadder,
  runtime?: SurfaceRuntime,
): () => void {
  roots.set(element, ladder);
  if (runtime) runtimeRoots.set(element, runtime);
  return () => {
    roots.delete(element);
    runtimeRoots.delete(element);
  };
}

export function ladderForSurfaceElement(
  element: HTMLElement,
): FocusLadder | undefined {
  let current: HTMLElement | null = element;
  while (current) {
    const ladder = roots.get(current);
    if (ladder) return ladder;
    current = current.parentElement;
  }
  return undefined;
}

export function surfaceRuntimeForElement(
  element: HTMLElement,
): SurfaceRuntime | undefined {
  let current: HTMLElement | null = element;
  while (current) {
    const runtime = runtimeRoots.get(current);
    if (runtime) return runtime;
    current = current.parentElement;
  }
  return undefined;
}

export function registerSurfaceDomNode(
  runtime: SurfaceRuntime,
  id: string,
  element: HTMLElement,
): () => void {
  let elementsById = surfaceElements.get(runtime);
  if (!elementsById) {
    elementsById = new Map();
    surfaceElements.set(runtime, elementsById);
  }

  let elements = elementsById.get(id);
  if (!elements) {
    elements = new Set();
    elementsById.set(id, elements);
  }

  elements.add(element);

  return () => {
    elements?.delete(element);
    if (elements?.size === 0) {
      elementsById?.delete(id);
    }
  };
}

export function surfaceElementsForIds(
  root: HTMLElement,
  ids: readonly string[],
  runtime?: SurfaceRuntime,
): HTMLElement[] {
  const out: HTMLElement[] = [];
  const seen = new Set<HTMLElement>();
  const activeRuntime = runtime ?? surfaceRuntimeForElement(root);
  const elementsById = activeRuntime
    ? surfaceElements.get(activeRuntime)
    : undefined;

  for (const id of ids) {
    const registered = elementsById?.get(id);
    if (registered) {
      let addedRegisteredElement = false;
      for (const element of registered) {
        const inRoot = root.contains(element);
        const inSameRuntimeLift =
          !inRoot &&
          activeRuntime !== undefined &&
          element.closest('[data-bx-lift]') !== null &&
          surfaceRuntimeForElement(element) === activeRuntime;
        if (
          !element.isConnected ||
          (!inRoot && !inSameRuntimeLift) ||
          seen.has(element)
        ) {
          continue;
        }
        out.push(element);
        seen.add(element);
        addedRegisteredElement = true;
      }
      if (addedRegisteredElement) continue;
    }

    const fallback = findSurfaceElementById(root, id);
    if (fallback && !seen.has(fallback)) {
      out.push(fallback);
      seen.add(fallback);
    }
  }

  return out;
}

export function surfaceElementForId(
  root: HTMLElement,
  id: string,
  runtime?: SurfaceRuntime,
): HTMLElement | null {
  return surfaceElementsForIds(root, [id], runtime)[0] ?? null;
}

export function registerSurfaceLiftDomRoot(
  element: HTMLElement,
  manager: LiftManager,
): () => void {
  liftRoots.set(element, manager);
  return () => liftRoots.delete(element);
}

export function liftManagerForSurfaceElement(
  element: HTMLElement,
): LiftManager | undefined {
  let current: HTMLElement | null = element;
  while (current) {
    const manager = liftRoots.get(current);
    if (manager) return manager;
    current = current.parentElement;
  }
  return undefined;
}

export function parentSurfaceIdForElement(element: HTMLElement): string | null {
  const parent = element.parentElement?.closest<HTMLElement>(
    '[data-ladder-id], [data-surface-component][id]',
  );
  return parent?.getAttribute('data-ladder-id') ?? parent?.id ?? null;
}

function findSurfaceElementById(
  root: HTMLElement,
  id: string,
): HTMLElement | null {
  if (surfaceElementMatchesId(root, id)) return root;
  for (const element of root.querySelectorAll<HTMLElement>(
    '[data-ladder-id], [data-id], [data-bx-grid-traversal-id], [id]',
  )) {
    if (surfaceElementMatchesId(element, id)) return element;
  }
  return null;
}

function surfaceElementMatchesId(element: HTMLElement, id: string): boolean {
  return (
    element.getAttribute('data-ladder-id') === id ||
    element.getAttribute('data-id') === id ||
    element.dataset['bxGridTraversalId'] === id ||
    element.id === id
  );
}
