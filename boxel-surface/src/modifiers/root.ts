// `surfaceRoot` — the host-agnostic surface coordination modifier.
//
// One of these wraps the OUTERMOST element that hosts a FocusLadder.
// Replaces the per-app boilerplate that every demo used to write
// (custom keydown handlers, custom background-click handlers,
// tabindex setup, etc.) with one declarative attachment:
//
//   <main {{surfaceRoot ladder}}>
//     ...
//   </main>
//
// WHAT IT INSTALLS
// ================
//
// 1. KEYBOARD ROUTING
//    Listens for keydown on the modified element. Skips events whose
//    target is a text-entry element (`<input>`, `<textarea>`,
//    `<select>`, `[contenteditable=true]`) — those keystrokes are
//    "for the editor", not for ladder nav. Otherwise uses the same
//    DOM-focus-first model as polymorph: Tab walks the surface tree,
//    arrows move across siblings, Enter descends into the first child,
//    and Escape walks to the parent during active navigation. After
//    that window, Escape clears the active surface selection. Hosts can
//    observe handled/unhandled keys through `onKey`, or suspend ladder
//    routing while a contained child surface owns keyboard through
//    `shouldRouteKey`.
//
// 2. BACKGROUND CLICK CLEAR
//    Listens for pointerdown anywhere inside the modified element.
//    Walks up from `event.target` looking for a `[data-ladder-id]`
//    ancestor. If none is found within the modified element, calls
//    `ladder.clear()` — the user clicked on the surface background
//    (not on any registered node), so focus + selection drop.
//    Hosts that bridge to other selection systems (e.g., Canvas →
//    xyflow) subscribe to ladder via `ladder.subscribe(cb)` and
//    mirror the clear into their own data model. The modifier itself
//    stays renderer-agnostic — it doesn't know about xyflow stores
//    or table state, just the ladder.
//
// 3. TABINDEX
//    Sets `tabindex="0"` on the modified element when missing, so
//    the page-root can receive focus and keydown events fire on it
//    after a click anywhere inside.
//
// LIFETIME
// ========
//
// One per surface root. Cleanup removes both listeners and (if we
// added the tabindex) restores the previous value. No outstanding
// references — safe to mount/unmount repeatedly.

import { modifier } from 'ember-modifier';

import type {
  FocusLadder,
  LadderSurface,
  TargetMode,
} from '../focus-ladder.ts';
import type {
  FociMode,
  FociMoveDirection,
  FociRevealIntent,
  FociTraversalOptions,
} from '../foci-store.ts';
import type { SurfaceRuntime } from '../surface-runtime.ts';
import {
  liftManagerForSurfaceElement,
  registerSurfaceDomRoot,
} from '../dom-registry.ts';
import {
  isSurfaceTextEntryTarget,
  surfaceTargetRetainsBrowserFocusAfterSelection,
  surfaceTargetOwnsKeyboardEvent,
} from '../keyboard.ts';

export type NavigationView = 'all' | 'targets';
type ChangeRoute = 'inline' | 'lifted' | 'auto';
type SurfaceDeselectReason = 'escape' | 'background';

const backgroundDeselectSurfaces = new Set([
  'space',
  'layout',
  'canvas',
  'scene',
  'grid',
  'scroll',
  'flow',
  'outline',
  'frame',
  'pane',
  'plane',
]);

function pathContainsPreserveFocus(event: Event): boolean {
  return event
    .composedPath()
    .some(
      (entry) =>
        entry instanceof Element &&
        (entry.hasAttribute('data-surface-preserve-focus') ||
          entry.hasAttribute('data-surface-key-scope') ||
          entry.closest('[data-surface-preserve-focus]') !== null ||
          entry.closest('[data-surface-key-scope]') !== null),
    );
}

function isEnabledDataAttribute(value: string | null): boolean {
  return value === '' || value === 'true';
}

function shouldDeselectBareSurfaceBackground(
  hit: HTMLElement,
  target: EventTarget | null,
): boolean {
  if (target !== hit) return false;

  const override = hit.getAttribute('data-surface-background');
  if (override === 'select') return false;
  if (override === 'deselect') return true;

  const surface = hit.getAttribute('data-surface');
  return surface !== null && backgroundDeselectSurfaces.has(surface);
}

function editableElements(element: HTMLElement): HTMLElement[] {
  return Array.from(
    element.querySelectorAll<HTMLElement>(
      '[data-surface-inline-edit="true"], input, textarea, select, [contenteditable]:not([contenteditable=false])',
    ),
  ).filter(
    (candidate, index, candidates) =>
      candidate.isConnected && candidates.indexOf(candidate) === index,
  );
}

function isEditorElement(element: Element | null): element is HTMLElement {
  return Boolean(
    element?.matches(
      '[data-surface-inline-edit="true"], input, textarea, select, [contenteditable]:not([contenteditable=false])',
    ),
  );
}

function changeEditorForSurface(surface: HTMLElement): HTMLElement | null {
  if (isEditorElement(surface)) return surface;

  const inlineEditors = editableElements(surface).filter(
    (candidate) =>
      candidate.getAttribute('data-surface-inline-edit') === 'true',
  );
  if (inlineEditors.length === 1) return inlineEditors[0]!;
  if (inlineEditors.length > 1) return null;

  const editors = editableElements(surface);
  return editors.length === 1 ? editors[0]! : null;
}

function focusChangeEditor(surface: HTMLElement): boolean {
  const editor = changeEditorForSurface(surface);
  if (!editor) return false;

  editor.focus({ preventScroll: true });
  requestAnimationFrame(() => {
    if (!editor.isConnected) return;
    editor.focus({ preventScroll: true });
  });
  setTimeout(() => {
    if (!editor.isConnected) return;
    editor.focus({ preventScroll: true });
  }, 0);
  return true;
}

function shouldFocusRootOnPointerDown(
  root: HTMLElement,
  target: EventTarget | null,
): boolean {
  if (!target || !(target instanceof Element)) return false;
  if (!root.contains(target)) return false;
  if (isSurfaceTextEntryTarget(target)) return false;
  const interactive = target.closest(
    'button, a[href], input, textarea, select, [contenteditable=true], [role="button"], [role="menuitem"], [role="option"], [tabindex]',
  );
  return interactive === null || interactive === root;
}

/** Predicate: should this ladder LEAVE ITSELF ALONE (not clear)
 *  given a click on `target`?
 *
 *  Two yes-answers:
 *
 *    (a) Target is inside `root` AND walked up to a [data-ladder-id]
 *        ancestor that's also inside root. The cell's own click
 *        handler will / has set focus.
 *
 *    (b) Target is OUTSIDE `root` (typical for a popover portaled
 *        to body / a canvas renderer / a top-layer dialog) but the
 *        nearest [data-ladder-id] ancestor's id is registered in
 *        OUR ladder. The lift belongs to us — the user is editing
 *        a cell we own, just in a portaled lift surface. Clearing
 *        here would close the editing context the user is actively
 *        working in.
 *
 *  Detached targets (target.isConnected === false) also return true.
 *  Rationale: a cell's pointerdown handler can call ladder.select(),
 *  which mutates tracked state and (in some Glimmer setups) flushes
 *  a re-render synchronously, which destroys the cell DOM, which
 *  detaches the original click target. Treating detached targets as
 *  ladder targets is the safer default: a real background click
 *  never has a detached target at this point.
 *
 *  Returns false to mean "this was a background click — clear". */
function clickedOnLadderTarget(
  root: HTMLElement,
  target: EventTarget | null,
  ladder: FocusLadder,
): boolean {
  if (!target || !(target instanceof Element)) return false;
  if (!target.isConnected) return true;
  if (target.closest('[data-surface-preserve-focus]')) return true;

  // Walk up looking for any [data-ladder-id] ancestor — could be a
  // registered cell inside root, or a portaled popover/dialog
  // marked with the source cell's id.
  const hit = target.closest('[data-ladder-id]');
  if (!hit) {
    // No ladder marker at all — definitely background.
    return false;
  }
  const id = hit.getAttribute('data-ladder-id');
  if (!id) return false;

  // (a) Hit is inside our root → directly registered surface.
  // Bare interiors of container-like surfaces count as background:
  // clicking empty document/canvas/grid space should drop the current
  // selection, not select the container and keep chrome lit up.
  if (root.contains(hit)) {
    return !shouldDeselectBareSurfaceBackground(hit as HTMLElement, target);
  }

  // (b) Hit is OUTSIDE our root (portaled lift). Belongs to us
  //     ONLY if its id is registered in our ladder.
  return ladder.getNode(id) !== null;
}

function surfaceElementFromTarget(
  root: HTMLElement,
  target: EventTarget | null,
): HTMLElement | null {
  if (!target || !(target instanceof Element)) return null;
  const hit = target.closest('[data-ladder-id]');
  if (!hit || !root.contains(hit)) return null;
  return hit as HTMLElement;
}

function magneticSelectionSurfaceFromTarget(
  root: HTMLElement,
  target: EventTarget | null,
): HTMLElement | null {
  if (!target || !(target instanceof Element)) return null;
  if (!root.contains(target)) return null;
  if (surfaceTargetRetainsBrowserFocusAfterSelection(target)) return null;

  const hit = target.closest<HTMLElement>(
    '[data-ladder-id][data-surface="cell"], [data-ladder-id][data-surface-component="cell"]',
  );
  if (!hit || !root.contains(hit) || hit === target) return null;
  if (hit.getAttribute('data-surface-pointer') === 'content-interactive') {
    return null;
  }
  return hit;
}

function focusMagneticSelectionSurface(surface: HTMLElement): void {
  const focusSurfaceElement = (): void => {
    if (!surface.isConnected) return;
    if (surface.ownerDocument.activeElement === surface) return;
    surface.focus({ preventScroll: true });
  };

  requestAnimationFrame(focusSurfaceElement);
  setTimeout(focusSurfaceElement, 0);
}

function surfaceIdFromTarget(
  root: HTMLElement,
  target: EventTarget | null,
  ladder: FocusLadder,
): string | null {
  const hit = surfaceElementFromTarget(root, target);
  const id = hit?.getAttribute('data-ladder-id') ?? null;
  if (!id || !ladder.getNode(id)) return null;
  return id;
}

function surfaceElementById(root: HTMLElement, id: string): HTMLElement | null {
  if (root.getAttribute('data-ladder-id') === id) return root;
  for (const element of root.querySelectorAll<HTMLElement>(
    '[data-ladder-id]',
  )) {
    if (element.getAttribute('data-ladder-id') === id) return element;
  }
  return null;
}

interface SurfaceFocusOptions extends FocusOptions {
  runtime?: SurfaceRuntime;
  syncRuntime?: boolean;
}

// Default policy: DOM focus, runtime focus, and runtime selection are one
// navigation target. They intentionally separate only while the runtime is
// holding an input/lift/menu or transfer session, where the source selection
// and the browser's active control are allowed to diverge.
function runtimeHasSplitFocus(runtime: SurfaceRuntime | undefined): boolean {
  if (!runtime) return false;
  const snapshot = runtime.snapshot();
  if (snapshot.input !== null) return true;
  const transfer = snapshot.transfer;
  if (!transfer) return false;
  if (transfer.kind === 'copy' && !transfer.destination) return false;
  if (transfer.kind === 'drag') return transfer.movedPastThreshold === true;
  return transfer.destination !== undefined;
}

function runtimeSelectionAlreadyOwnsFocus(
  runtime: SurfaceRuntime,
  id: string,
): boolean {
  const snapshot = runtime.snapshot();
  if (snapshot.focusedId !== id) return false;

  const node = runtime.node(id);
  if (node?.policy?.selection === 'none') return true;

  return Object.values(snapshot.selections).some(
    (selection) => selection.headId === id && selection.ids.includes(id),
  );
}

function runtimeHasActiveRangeHead(
  runtime: SurfaceRuntime,
  id: string,
): boolean {
  return Object.values(runtime.snapshot().selections).some(
    (selection) => selection.headId === id && selection.ids.length > 1,
  );
}

function syncRuntimeToNavigationFocus(
  runtime: SurfaceRuntime | undefined,
  id: string,
): void {
  if (!runtime || runtimeHasSplitFocus(runtime)) return;
  if (!runtime.node(id)) return;
  if (runtimeSelectionAlreadyOwnsFocus(runtime, id)) return;
  if (runtimeHasActiveRangeHead(runtime, id)) return;
  runtime.select(id);
}

function activeRuntimeFocusId(
  runtime: SurfaceRuntime | undefined,
): string | null {
  if (!runtime || runtimeHasSplitFocus(runtime)) return null;
  return runtime.snapshot().focusedId;
}

function focusSurface(
  root: HTMLElement,
  ladder: FocusLadder,
  id: string,
  options: SurfaceFocusOptions = {},
): boolean {
  const { runtime, syncRuntime = true, ...focusOptions } = options;
  const target = surfaceElementById(root, id);
  if (!target) return false;
  if (syncRuntime) syncRuntimeToNavigationFocus(runtime, id);
  if (ladder.focusedId !== id) {
    ladder.focusId(id);
  }
  target.focus(focusOptions);
  return true;
}

function revealSurface(
  root: HTMLElement,
  reveal: FociRevealIntent | undefined,
): void {
  if (!reveal || (reveal.block === 'none' && reveal.inline === 'none')) return;
  const target = surfaceElementById(root, reveal.targetId);
  target?.scrollIntoView({
    block: reveal.block === 'none' ? 'nearest' : reveal.block,
    inline: reveal.inline === 'none' ? 'nearest' : reveal.inline,
  });
}

function targetModeForRoot(root: HTMLElement): TargetMode {
  const mode = root.getAttribute('data-surface-mode');
  const inspect = isEnabledDataAttribute(
    root.getAttribute('data-surface-inspect'),
  );
  if (mode === 'use' && inspect) return 'inspect';
  if (mode === 'use' || mode === 'change' || mode === 'inspect') return mode;
  return 'use';
}

function runtimeModeForTargetMode(mode: TargetMode): FociMode {
  return mode === 'debug' ? 'debug' : mode;
}

function runtimeTraversalOptionsForRoot(
  root: HTMLElement,
  mode: TargetMode,
): FociTraversalOptions {
  return {
    mode: runtimeModeForTargetMode(mode),
    inspect: isEnabledDataAttribute(root.getAttribute('data-surface-inspect')),
  };
}

function runtimeTraversalIds(
  root: HTMLElement,
  runtime: SurfaceRuntime | undefined,
  mode: TargetMode,
  view: NavigationView,
): readonly string[] | null {
  if (!runtime || view === 'all') return null;
  return runtime.traversalSet(runtimeTraversalOptionsForRoot(root, mode)).ids;
}

function runtimeNavigationIdFor(
  root: HTMLElement,
  runtime: SurfaceRuntime | undefined,
  id: string | null,
  mode: TargetMode,
  view: NavigationView,
): string | null {
  if (!runtime || view === 'all' || !id) return null;
  const ids = runtimeTraversalIds(root, runtime, mode, view);
  if (!ids) return null;
  const traversalIds = new Set(ids);
  let cursor = runtime.node(id);
  while (cursor) {
    if (traversalIds.has(cursor.id)) return cursor.id;
    if (cursor.parentId === null) return null;
    cursor = runtime.node(cursor.parentId);
  }
  return null;
}

function runtimeStepNavigationId(
  root: HTMLElement,
  runtime: SurfaceRuntime | undefined,
  id: string | null,
  mode: TargetMode,
  view: NavigationView,
  delta: 1 | -1,
): string | null {
  const ids = runtimeTraversalIds(root, runtime, mode, view);
  if (!ids || ids.length === 0) return null;
  if (!id) return delta > 0 ? ids[0]! : ids[ids.length - 1]!;
  const current = runtimeNavigationIdFor(root, runtime, id, mode, view);
  if (!current) return delta > 0 ? ids[0]! : ids[ids.length - 1]!;
  const index = ids.indexOf(current);
  return index >= 0 ? (ids[index + delta] ?? null) : null;
}

function runtimeFirstChildNavigationId(
  root: HTMLElement,
  runtime: SurfaceRuntime | undefined,
  id: string,
  mode: TargetMode,
  view: NavigationView,
): string | null {
  const ids = runtimeTraversalIds(root, runtime, mode, view);
  if (!runtime || !ids) return null;
  const traversalIds = new Set(ids);
  const visit = (parentId: string): string | null => {
    for (const node of runtime.registrations()) {
      if (node.parentId !== parentId) continue;
      if (traversalIds.has(node.id)) return node.id;
      const descendant = visit(node.id);
      if (descendant) return descendant;
    }
    return null;
  };
  return visit(id);
}

function runtimeParentNavigationId(
  root: HTMLElement,
  runtime: SurfaceRuntime | undefined,
  id: string,
  mode: TargetMode,
  view: NavigationView,
): string | null {
  if (!runtime || view === 'all') return null;
  const ids = runtimeTraversalIds(root, runtime, mode, view);
  if (!ids) return null;
  const traversalIds = new Set(ids);
  let cursor = runtime.node(id);
  while (cursor?.parentId) {
    cursor = runtime.node(cursor.parentId);
    if (cursor && traversalIds.has(cursor.id)) return cursor.id;
  }
  return null;
}

function directionForArrowKey(key: string): FociMoveDirection {
  switch (key) {
    case 'ArrowLeft':
      return 'left';
    case 'ArrowRight':
      return 'right';
    case 'ArrowUp':
      return 'up';
    case 'ArrowDown':
      return 'down';
    default:
      throw new Error(`Unsupported arrow key: ${key}`);
  }
}

function changeRouteForRoot(root: HTMLElement): ChangeRoute {
  const route = root.getAttribute('data-surface-change-route');
  if (route === 'inline' || route === 'lifted' || route === 'auto') {
    return route;
  }
  return 'auto';
}

function activeLiftOwnsDomFocus(root: HTMLElement): boolean {
  const manager = liftManagerForSurfaceElement(root);
  if (!manager?.isOpen) return false;
  return manager.kind === 'edit' || manager.kind === 'tools';
}

function liftSourceIdForSurface(surface: HTMLElement): string | null {
  return surface.getAttribute('data-surface-lift-source');
}

function singleDescendantLiftSourceId(surface: HTMLElement): string | null {
  const ids = new Set<string>();
  for (const descendant of surface.querySelectorAll<HTMLElement>(
    '[data-surface-lift-source]',
  )) {
    const id = descendant.getAttribute('data-surface-lift-source');
    if (id) ids.add(id);
    if (ids.size > 1) return null;
  }
  return [...ids][0] ?? null;
}

function surfaceKindForElement(
  surface: HTMLElement,
): LadderSurface | undefined {
  const kind = surface.getAttribute('data-surface');
  return kind as LadderSurface | undefined;
}

function openChangeLiftForSurface(
  root: HTMLElement,
  surface: HTMLElement,
): boolean {
  const manager = liftManagerForSurfaceElement(root);
  if (!manager) return false;

  const sourceId = liftSourceIdForSurface(surface);
  if (sourceId) {
    if (manager.openForModeBySourceId(sourceId, 'change', 'change-activate')) {
      return true;
    }
  }

  const descendantSourceId = singleDescendantLiftSourceId(surface);
  if (!descendantSourceId) return false;

  const sourceOverride: Parameters<
    NonNullable<typeof manager.openForModeBySourceId>
  >[3] = {
    id: surface.getAttribute('data-ladder-id') ?? descendantSourceId,
    path: surface.getAttribute('data-surface-coordinate') ?? undefined,
    element: surface,
  };
  const surfaceKind = surfaceKindForElement(surface);
  if (surfaceKind) sourceOverride.surface = surfaceKind;

  return manager.openForModeBySourceId(
    descendantSourceId,
    'change',
    'change-activate',
    sourceOverride,
  );
}

function activateChangeTarget(
  root: HTMLElement,
  surface: HTMLElement,
): boolean {
  const route = changeRouteForRoot(root);

  if (route !== 'lifted' && focusChangeEditor(surface)) {
    return true;
  }

  if (route !== 'inline' && openChangeLiftForSurface(root, surface)) {
    return true;
  }

  return route === 'inline' ? focusChangeEditor(surface) : false;
}

function navigationViewForOptions(opts: RootOptions): NavigationView {
  return opts.navigationView ?? 'targets';
}

function navigationIdFor(
  ladder: FocusLadder,
  id: string | null,
  mode: TargetMode,
  view: NavigationView,
): string | null {
  if (view === 'all') return id && ladder.getNode(id) ? id : null;
  return ladder.targetIdFor(id, mode);
}

function firstNavigationId(
  ladder: FocusLadder,
  mode: TargetMode,
  view: NavigationView,
): string | null {
  return view === 'all' ? ladder.firstId() : ladder.firstTargetId(mode);
}

function lastNavigationId(
  ladder: FocusLadder,
  mode: TargetMode,
  view: NavigationView,
): string | null {
  return view === 'all' ? ladder.lastId() : ladder.lastTargetId(mode);
}

function nextNavigationId(
  ladder: FocusLadder,
  id: string,
  mode: TargetMode,
  view: NavigationView,
): string | null {
  return view === 'all'
    ? ladder.nextInTree(id)
    : ladder.nextTargetInTree(id, mode);
}

function prevNavigationId(
  ladder: FocusLadder,
  id: string,
  mode: TargetMode,
  view: NavigationView,
): string | null {
  return view === 'all'
    ? ladder.prevInTree(id)
    : ladder.prevTargetInTree(id, mode);
}

function firstChildNavigationId(
  ladder: FocusLadder,
  id: string,
  mode: TargetMode,
  view: NavigationView,
): string | null {
  if (view === 'targets') return ladder.firstChildTargetId(id, mode);
  return ladder.childrenOf(id)[0] ?? null;
}

function parentNavigationId(
  ladder: FocusLadder,
  id: string,
  mode: TargetMode,
  view: NavigationView,
): string | null {
  return view === 'all' ? ladder.parentOf(id) : ladder.parentTargetId(id, mode);
}

function dispatchSurfaceCommand(
  surface: HTMLElement,
  command: 'surface-activate' | 'surface-expand' | 'surface-collapse',
  originalEvent: KeyboardEvent,
): boolean {
  const event = new CustomEvent(command, {
    bubbles: false,
    cancelable: true,
    detail: { originalEvent },
  });
  const wasNotCanceled = surface.dispatchEvent(event);
  if (wasNotCanceled) return false;
  originalEvent.preventDefault();
  originalEvent.stopPropagation();
  return true;
}

function scopedPatternElement(
  root: HTMLElement,
  currentId: string,
  pattern: string,
): HTMLElement | null {
  const surface = surfaceElementById(root, currentId);
  return (
    surface?.closest<HTMLElement>(`[data-surface-pattern="${pattern}"]`) ?? null
  );
}

function navigationIdsWithin(
  scope: HTMLElement,
  ladder: FocusLadder,
  mode: TargetMode,
  view: NavigationView,
): string[] {
  const ids: string[] = [];
  for (const surface of scope.querySelectorAll<HTMLElement>(
    '[data-ladder-id]',
  )) {
    const id = surface.getAttribute('data-ladder-id');
    if (!id || ids.includes(id)) continue;
    if (view === 'all' || ladder.isEligibleTarget(id, mode)) ids.push(id);
  }
  return ids;
}

function scopedNavigationId(
  root: HTMLElement,
  ladder: FocusLadder,
  currentId: string,
  mode: TargetMode,
  view: NavigationView,
  delta: 1 | -1,
): string | null {
  const scope = scopedPatternElement(root, currentId, 'disclosure-tree');
  if (!scope) return null;

  const ids = navigationIdsWithin(scope, ladder, mode, view);
  const currentNavigationId = navigationIdFor(ladder, currentId, mode, view);
  if (!currentNavigationId) return ids[0] ?? null;
  const index = ids.indexOf(currentNavigationId);
  if (index < 0) return ids[0] ?? null;
  return ids[index + delta] ?? null;
}

function handleDisclosureTreeKey(
  root: HTMLElement,
  ladder: FocusLadder,
  runtime: SurfaceRuntime | undefined,
  currentId: string,
  mode: TargetMode,
  view: NavigationView,
  event: KeyboardEvent,
): boolean {
  const scope = scopedPatternElement(root, currentId, 'disclosure-tree');
  if (!scope) return false;
  const surface = surfaceElementById(root, currentId);
  if (!surface || !scope.contains(surface)) return false;

  if (event.key === 'Enter') {
    return dispatchSurfaceCommand(surface, 'surface-activate', event);
  }

  if (event.key === 'ArrowRight') {
    if (
      surface.getAttribute('data-surface-expandable') === 'true' &&
      surface.getAttribute('data-surface-expanded') !== 'true' &&
      dispatchSurfaceCommand(surface, 'surface-expand', event)
    ) {
      return true;
    }
  }

  if (event.key === 'ArrowLeft') {
    if (
      surface.getAttribute('data-surface-expandable') === 'true' &&
      surface.getAttribute('data-surface-expanded') === 'true' &&
      dispatchSurfaceCommand(surface, 'surface-collapse', event)
    ) {
      return true;
    }
    const parentId = parentNavigationId(ladder, currentId, mode, view);
    const parentSurface = parentId ? surfaceElementById(root, parentId) : null;
    if (parentId && parentSurface && scope.contains(parentSurface)) {
      event.preventDefault();
      return focusSurface(root, ladder, parentId, { runtime });
    }
  }

  return false;
}

function closestActivatableSurface(
  root: HTMLElement,
  surface: HTMLElement | null,
): HTMLElement | null {
  const activatable =
    surface?.closest<HTMLElement>('[data-surface-activatable="true"]') ?? null;
  return activatable && root.contains(activatable) ? activatable : null;
}

/**
 * The modifier. Public API:
 *
 *   <main {{surfaceRoot this.ladder}}>
 *
 * The modifier accepts a single positional arg: the FocusLadder it
 * coordinates. Hosts that want to skip one of the two effects
 * (e.g., they own keyboard handling themselves) can pass options:
 *
 *   <main {{surfaceRoot this.ladder skipKeyboard=true}}>
 *
 * Both effects default ON.
 */
export interface RootOptions {
  /** Foci runtime for policy/store-driven traversal and decals. */
  runtime?: SurfaceRuntime;
  /** Skip the keyboard routing (keydown → DOM focus movement + ladder sync).
   *  Default false — the modifier installs the keymap. */
  skipKeyboard?: boolean;
  /** Skip the background-click clearing (pointerdown outside any
   *  registered ladder node → ladder.clear). Default false. */
  skipBackgroundClick?: boolean;
  /** Disable the default Escape-to-deselect behavior. Default false. */
  skipEscapeDeselect?: boolean;
  /** Host-side guard for contained child surfaces. Return false when
   *  a child editor/lift currently owns keyboard; surfaceRoot will
   *  skip `ladder.handleKey` and still notify `onKey`. */
  shouldRouteKey?: (event: KeyboardEvent, ladder: FocusLadder) => boolean;
  /** Which coordinate projection keyboard traversal should use.
   *  `all` crawls every registered surface coordinate for debugging.
   *  `targets` crawls the purposeful target projection for product use. */
  navigationView?: NavigationView;
  /** Observe surface keys after the shared ladder has had first
   *  chance to route them. `handled` is true when the ladder moved
   *  focus and called preventDefault. Hosts use unhandled Enter/F2
   *  to open a negotiated lift at the focused leaf. */
  onKey?: (event: KeyboardEvent, ladder: FocusLadder, handled: boolean) => void;
}

const surfaceRoot = modifier<{
  Element: HTMLElement;
  Args: { Positional: [FocusLadder]; Named: RootOptions };
}>((element, [ladder], opts = {}) => {
  // Tabindex setup — make the root focusable so keydown fires here
  // after any click inside. We restore the prior value on cleanup
  // so we don't leak focusability into hot-reload scenarios.
  const priorTabindex = element.getAttribute('tabindex');
  const didAddTabindex = priorTabindex === null && !opts.skipKeyboard;
  if (didAddTabindex) {
    element.setAttribute('tabindex', '0');
  }
  const unregisterDomRoot = registerSurfaceDomRoot(
    element,
    ladder,
    opts.runtime,
  );
  let syncFocusTimer: ReturnType<typeof setTimeout> | undefined;

  const shouldDeselectOnEscape = (): boolean =>
    opts.skipEscapeDeselect !== true;

  const canRootOwnDeselectForEvent = (event: Event): boolean => {
    const target = event.target;
    if (!target || !(target instanceof Element)) return true;
    if (pathContainsPreserveFocus(event)) return false;
    if (activeLiftOwnsDomFocus(element)) return false;
    return true;
  };

  const clearSurfaceSelection = (
    reason: SurfaceDeselectReason,
    focusRoot: boolean,
    event?: Event,
  ): boolean => {
    const runtimeSnapshot = opts.runtime?.snapshot();
    const runtimeHasInteraction = Boolean(
      runtimeSnapshot?.focusedId ||
      runtimeSnapshot?.hoveredId ||
      Object.keys(runtimeSnapshot?.selections ?? {}).length > 0,
    );
    if (
      ladder.focusedId === null &&
      ladder.hoveredId === null &&
      !runtimeHasInteraction
    ) {
      return false;
    }

    ladder.clear();
    ladder.hoverId(null);
    if (!runtimeHasSplitFocus(opts.runtime)) {
      opts.runtime?.clearInteractionState();
    }
    event?.preventDefault();
    event?.stopPropagation();
    element.dispatchEvent(
      new CustomEvent('surface-deselect', {
        bubbles: true,
        detail: { reason },
      }),
    );

    if (focusRoot) {
      element.focus({ preventScroll: true });
    }

    return true;
  };

  let lastNavAt = 0;
  const markNav = (): void => {
    lastNavAt = Date.now();
  };
  const isNavRecent = (): boolean => Date.now() - lastNavAt < 2000;

  const onFocusin = (event: FocusEvent): void => {
    if (
      event.target instanceof Element &&
      event.target.closest('[data-surface-preserve-focus]')
    ) {
      return;
    }

    const id = surfaceIdFromTarget(element, event.target, ladder);
    const mode = targetModeForRoot(element);
    const navigationView = navigationViewForOptions(opts);
    const runtime = opts.runtime;
    const nextId =
      runtimeNavigationIdFor(element, runtime, id, mode, navigationView) ??
      navigationIdFor(ladder, id, mode, navigationView);
    if (nextId) {
      syncRuntimeToNavigationFocus(runtime, nextId);
      ladder.focusId(nextId);
    }

    const magneticSurface = magneticSelectionSurfaceFromTarget(
      element,
      event.target,
    );
    if (
      magneticSurface &&
      magneticSurface.getAttribute('data-ladder-id') === nextId
    ) {
      focusMagneticSelectionSurface(magneticSurface);
    }
  };

  const handlePolymorphKey = (event: KeyboardEvent): boolean => {
    const runtime = opts.runtime;
    const rawCurrentId = surfaceIdFromTarget(element, event.target, ladder);
    const mode = targetModeForRoot(element);
    const navigationView = navigationViewForOptions(opts);
    const activeNavigationId =
      runtimeNavigationIdFor(
        element,
        runtime,
        rawCurrentId,
        mode,
        navigationView,
      ) ?? navigationIdFor(ladder, rawCurrentId, mode, navigationView);
    const currentId =
      runtimeNavigationIdFor(
        element,
        runtime,
        ladder.focusedId,
        mode,
        navigationView,
      ) ??
      ladder.focusedId ??
      activeNavigationId;

    if (event.key === 'Escape') {
      if (isNavRecent()) {
        markNav();
        const parentId = currentId
          ? (runtimeParentNavigationId(
              element,
              runtime,
              currentId,
              mode,
              navigationView,
            ) ?? parentNavigationId(ladder, currentId, mode, navigationView))
          : null;
        if (parentId && focusSurface(element, ladder, parentId, { runtime })) {
          event.preventDefault();
          event.stopPropagation();
          return true;
        }
      }

      return shouldDeselectOnEscape()
        ? clearSurfaceSelection('escape', true, event)
        : false;
    }

    if (event.key === 'Tab') {
      markNav();

      let nextId: string | null = null;
      if (currentId) {
        nextId = event.shiftKey
          ? (runtimeStepNavigationId(
              element,
              runtime,
              currentId,
              mode,
              navigationView,
              -1,
            ) ?? prevNavigationId(ladder, currentId, mode, navigationView))
          : (runtimeStepNavigationId(
              element,
              runtime,
              currentId,
              mode,
              navigationView,
              1,
            ) ?? nextNavigationId(ladder, currentId, mode, navigationView));
      }
      nextId ??= event.shiftKey
        ? (runtimeStepNavigationId(
            element,
            runtime,
            null,
            mode,
            navigationView,
            -1,
          ) ?? lastNavigationId(ladder, mode, navigationView))
        : (runtimeStepNavigationId(
            element,
            runtime,
            null,
            mode,
            navigationView,
            1,
          ) ?? firstNavigationId(ladder, mode, navigationView));
      if (!nextId) return false;
      event.preventDefault();
      return focusSurface(element, ladder, nextId, { runtime });
    }

    if (!currentId) return false;

    if (
      handleDisclosureTreeKey(
        element,
        ladder,
        runtime,
        currentId,
        mode,
        navigationView,
        event,
      )
    ) {
      markNav();
      return true;
    }

    const currentSurface = surfaceElementById(element, currentId);

    if (mode === 'change' && (event.key === 'Enter' || event.key === 'F2')) {
      const surface = currentSurface;
      if (surface && activateChangeTarget(element, surface)) {
        event.preventDefault();
        event.stopPropagation();
        markNav();
        return true;
      }
      if (event.key === 'F2') return false;
    }

    if (event.key === 'Enter') {
      const activationSurface = closestActivatableSurface(
        element,
        currentSurface,
      );
      if (
        activationSurface &&
        dispatchSurfaceCommand(activationSurface, 'surface-activate', event)
      ) {
        markNav();
        return true;
      }
      const firstChildId = firstChildNavigationId(
        ladder,
        currentId,
        mode,
        navigationView,
      );
      const runtimeChildId = runtimeFirstChildNavigationId(
        element,
        runtime,
        currentId,
        mode,
        navigationView,
      );
      const targetChildId = runtimeChildId ?? firstChildId;
      if (!targetChildId) return false;
      event.preventDefault();
      markNav();
      return focusSurface(element, ladder, targetChildId, { runtime });
    }

    if (
      event.key === 'ArrowLeft' ||
      event.key === 'ArrowRight' ||
      event.key === 'ArrowUp' ||
      event.key === 'ArrowDown'
    ) {
      if (runtime) {
        const result = runtime.dispatch({
          type: 'move',
          direction: directionForArrowKey(event.key),
          shift: event.shiftKey,
          mode: runtimeModeForTargetMode(mode),
        });
        const targetId =
          result.intent?.type === 'move-selection'
            ? result.intent.targetId
            : runtime.snapshot().focusedId;
        if (
          targetId &&
          focusSurface(element, ladder, targetId, {
            runtime,
            syncRuntime: false,
          })
        ) {
          revealSurface(element, result.reveal);
          event.preventDefault();
          event.stopPropagation();
          markNav();
          return true;
        }
        if (result.handled || result.reason === 'edge') {
          event.preventDefault();
          event.stopPropagation();
          markNav();
          return true;
        }
      }

      const delta =
        event.key === 'ArrowLeft' || event.key === 'ArrowUp' ? -1 : 1;
      const scopedId =
        event.key === 'ArrowUp' || event.key === 'ArrowDown'
          ? scopedNavigationId(
              element,
              ladder,
              currentId,
              mode,
              navigationView,
              delta,
            )
          : null;
      const nextId =
        scopedId ??
        (delta < 0
          ? (runtimeStepNavigationId(
              element,
              runtime,
              currentId,
              mode,
              navigationView,
              -1,
            ) ?? prevNavigationId(ladder, currentId, mode, navigationView))
          : (runtimeStepNavigationId(
              element,
              runtime,
              currentId,
              mode,
              navigationView,
              1,
            ) ?? nextNavigationId(ladder, currentId, mode, navigationView)));
      if (!nextId) {
        event.preventDefault();
        event.stopPropagation();
        return true;
      }

      event.preventDefault();
      markNav();
      return focusSurface(element, ladder, nextId, { runtime });
    }

    return false;
  };

  // Keyboard routing.
  const onKeydown = (event: KeyboardEvent): void => {
    if (opts.skipKeyboard) return;
    if (event.defaultPrevented) {
      opts.onKey?.(event, ladder, false);
      return;
    }
    if (pathContainsPreserveFocus(event)) {
      opts.onKey?.(event, ladder, false);
      return;
    }
    if (
      event.key === 'Escape' &&
      shouldDeselectOnEscape() &&
      canRootOwnDeselectForEvent(event) &&
      isSurfaceTextEntryTarget(event.target)
    ) {
      const handled = clearSurfaceSelection('escape', true, event);
      opts.onKey?.(event, ladder, handled);
      return;
    }
    if (surfaceTargetOwnsKeyboardEvent(event)) return;
    if (opts.shouldRouteKey?.(event, ladder) === false) {
      opts.onKey?.(event, ladder, false);
      return;
    }
    const handled = handlePolymorphKey(event);
    opts.onKey?.(event, ladder, handled);
  };

  // Background-click clearing. Listens on the DOCUMENT (not just
  // this element) so a click in ANOTHER pane / outside the page
  // root also clears this ladder. Without this, multi-pane apps
  // (widget-lab grid + canvas) preserve focus in pane A while the
  // user clicks in pane B — both ladders show focused state
  // simultaneously, which doesn't match user expectations.
  //
  // The check is the same in both directions:
  //   - Click landed inside this surface root, on a ladder node
  //     → leave alone (the cell's own click handler set focus).
  //   - Click landed inside this surface root, on background
  //     → clear (no ladder node was hit).
  //   - Click landed OUTSIDE this surface root entirely
  //     → clear (focus moved to a different pane / page bg).
  //
  // Capture phase so we run BEFORE bubble-phase handlers, then
  // pointerdown specifically (not click) so the clear happens
  // BEFORE any focus-stealing logic the cell registered — matches
  // the user's mental model of "click and drag to deselect"
  // working on mousedown, not on the trailing mouseup.
  const onDocPointerDown = (event: PointerEvent): void => {
    if (opts.skipBackgroundClick) return;
    if (shouldFocusRootOnPointerDown(element, event.target)) {
      element.focus({ preventScroll: true });
    }
    if (clickedOnLadderTarget(element, event.target, ladder)) return;
    clearSurfaceSelection(
      'background',
      event.target instanceof Node && element.contains(event.target),
    );
  };

  const clearPendingFocusSync = (): void => {
    if (syncFocusTimer === undefined) return;
    clearTimeout(syncFocusTimer);
    syncFocusTimer = undefined;
  };

  const syncDomFocusToLadder = (): void => {
    const runtime = opts.runtime;
    if (
      runtimeHasSplitFocus(runtime) ||
      activeLiftOwnsDomFocus(element) ||
      surfaceTargetRetainsBrowserFocusAfterSelection(document.activeElement)
    ) {
      clearPendingFocusSync();
      return;
    }
    const focusedId = activeRuntimeFocusId(runtime) ?? ladder.focusedId;
    if (!focusedId) {
      clearPendingFocusSync();
      return;
    }
    const magneticSurface = magneticSelectionSurfaceFromTarget(
      element,
      document.activeElement,
    );
    if (
      magneticSurface &&
      magneticSurface.getAttribute('data-ladder-id') === focusedId
    ) {
      focusMagneticSelectionSurface(magneticSurface);
      return;
    }
    const activeId = surfaceIdFromTarget(
      element,
      document.activeElement,
      ladder,
    );
    const mode = targetModeForRoot(element);
    const navigationView = navigationViewForOptions(opts);
    const activeNavigationId =
      runtimeNavigationIdFor(
        element,
        runtime,
        activeId,
        mode,
        navigationView,
      ) ?? navigationIdFor(ladder, activeId, mode, navigationView);
    if (activeNavigationId === focusedId) {
      clearPendingFocusSync();
      return;
    }
    clearPendingFocusSync();
    syncFocusTimer = setTimeout(() => {
      syncFocusTimer = undefined;
      if (runtimeHasSplitFocus(opts.runtime)) return;
      if (activeLiftOwnsDomFocus(element)) return;
      if (
        surfaceTargetRetainsBrowserFocusAfterSelection(document.activeElement)
      )
        return;
      const nextFocusedId =
        activeRuntimeFocusId(opts.runtime) ?? ladder.focusedId;
      if (!nextFocusedId) return;
      const nextActiveId = surfaceIdFromTarget(
        element,
        document.activeElement,
        ladder,
      );
      const nextActiveNavigationId =
        runtimeNavigationIdFor(
          element,
          opts.runtime,
          nextActiveId,
          targetModeForRoot(element),
          navigationViewForOptions(opts),
        ) ??
        navigationIdFor(
          ladder,
          nextActiveId,
          targetModeForRoot(element),
          navigationViewForOptions(opts),
        );
      if (nextActiveNavigationId === nextFocusedId) return;
      focusSurface(element, ladder, nextFocusedId, {
        runtime: opts.runtime,
        syncRuntime: false,
        preventScroll: true,
      });
    }, 0);
  };
  const unsubscribeFocusSync = ladder.subscribe(syncDomFocusToLadder);
  const unsubscribeRuntimeFocusSync =
    opts.runtime?.subscribeSelection(syncDomFocusToLadder);

  element.addEventListener('keydown', onKeydown);
  element.addEventListener('focusin', onFocusin);
  document.addEventListener('pointerdown', onDocPointerDown, true);

  return () => {
    element.removeEventListener('keydown', onKeydown);
    element.removeEventListener('focusin', onFocusin);
    document.removeEventListener('pointerdown', onDocPointerDown, true);
    unsubscribeFocusSync();
    unsubscribeRuntimeFocusSync?.();
    if (syncFocusTimer !== undefined) clearTimeout(syncFocusTimer);
    unregisterDomRoot();
    if (didAddTabindex) {
      element.removeAttribute('tabindex');
    }
  };
});

export default surfaceRoot;
