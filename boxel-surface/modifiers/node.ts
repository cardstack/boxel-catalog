// `surfaceNode` — marks a real product element as a registered
// surface node inside a FocusLadder.
//
// Use `surfaceRoot` once on the outer host that owns the ladder, then
// attach `surfaceNode` to each concrete surface element. This keeps
// templates readable: the element remains the actual product DOM, while
// surface identity, ladder registration, click selection, and data hooks
// are supplied by the surface system.
//
//   <article
//     class="itinerary-card"
//     {{surfaceNode this.ladder id="booking-card" surface="frame" parentId="itinerary"}}
//   >
//     ...real content...
//   </article>

import { modifier } from 'ember-modifier';

import type {
  FocusLadder,
  LadderSurface,
  Target,
  TargetScope,
} from '../focus-ladder.ts';
import type {
  FociGridCoordinate,
  FociNodeRegistration,
  FociNodePolicy,
} from '../foci-store.ts';
import type { SurfaceRuntime } from '../surface-runtime.ts';
import {
  ladderForSurfaceElement,
  liftManagerForSurfaceElement,
  parentSurfaceIdForElement,
  registerSurfaceDomNode,
  registerSurfaceLiftDomRoot,
  surfaceRuntimeForElement,
} from '../dom-registry.ts';
import type { LiftEdges, LiftManager, LiftSource } from '../lift-edges.ts';
import {
  isSurfaceTextEntryTarget,
  surfaceTargetRetainsBrowserFocusAfterSelection,
} from '../keyboard.ts';

type SurfaceNodeMode = 'use' | 'change' | 'inspect';
type SurfacePathPart = string | number | boolean;
type SurfaceCoordinateSource =
  | 'explicit'
  | 'identity'
  | 'context'
  | 'generated';

const actionRoles = new Set([
  'button',
  'link',
  'menuitem',
  'menuitemcheckbox',
  'menuitemradio',
  'option',
  'switch',
  'tab',
]);

const fieldRoles = new Set([
  'checkbox',
  'combobox',
  'radio',
  'searchbox',
  'slider',
  'spinbutton',
  'textbox',
]);

const rangeItemRoles = new Set([
  'cell',
  'columnheader',
  'gridcell',
  'listitem',
  'row',
  'rowheader',
  'treeitem',
]);

const objectRoles = new Set(['article', 'document', 'figure', 'img', 'region']);

const chromeRoles = new Set([
  'banner',
  'complementary',
  'contentinfo',
  'navigation',
  'search',
  'status',
  'toolbar',
]);

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

export interface NodeOptions {
  /** Shared semantic runtime. When omitted, the modifier uses the runtime attached to the owning ladder. */
  runtime?: SurfaceRuntime;
  /** Stable id, unique within the owning FocusLadder. */
  id?: string;
  /** Stable identity shared by alternate presentations of the same thing. */
  focusKey?: string;
  /** Runtime product coordinate. The modifier may refine context-derived values from the DOM tree. */
  coordinate?: string;
  /** Coordinate-space schema this surface defines for descendants. */
  coordinateSpace?: string;
  /** Local coordinate inside the nearest parent coordinate space. */
  localCoordinate?: string;
  /** Where the proposed coordinate came from. Context/generated values can be DOM-refined. */
  coordinateSource?: SurfaceCoordinateSource;
  /** Local product-path segments appended to the nearest parent path. */
  keyParts?: SurfacePathPart[];
  /** True when the component used a fallback/generated id. */
  generatedId?: boolean;
  /** Surface kind represented by the real DOM element. */
  surface?: LadderSurface;
  /** Purposeful selection/navigation target role. */
  target?: Target;
  /** Optional target-scope boundary introduced by this surface. */
  targetScope?: TargetScope;
  /** Explicit runtime scope override. Prefer presets/targets first. */
  scopeId?: string;
  /** Explicit runtime scope kind override. Prefer presets/targets first. */
  scopeKind?: TargetScope;
  /** Runtime compiler policy for this surface. */
  policy?: FociNodePolicy;
  /** Grid coordinate used by runtime-owned sheet movement and range logic. */
  grid?: FociGridCoordinate;
  /** Parent surface id, or null/omitted for the root child. */
  parentId?: string | null;
  /** Disable default click-to-select when the host owns selection itself. */
  skipClick?: boolean;
  /** Ambient surface mode. Use mode keeps ordinary surfaces out of the tab order. */
  mode?: SurfaceNodeMode;
  /** Enables inspection hover/selection overlay independently from use/change mode. */
  inspect?: boolean;
  /** Surface-level selection callback. Fired when this surface receives DOM focus. */
  onSelect?: (event: Event) => void;
  /** Surface-level activation callback. Fired by double-click or Enter on this surface. */
  onActivate?: (event: Event) => void;
  /** Scroll a corresponding anchor into view when this surface is selected. */
  scrollOnSelect?: boolean;
  /** Anchor key to scroll when selected. Defaults to this surface's coordinate/focus key. */
  scrollTarget?: string;
  /** Anchor key this surface exposes as a scroll destination. */
  scrollAnchor?: string;
  /** Hover signal emitted by this surface to mark corresponding anchors. */
  hoverSignal?: string;
  /** Anchor key that receives correspondence hover marking. */
  hoverAnchor?: string;
  /** Disclosure state for tree/outline-like surfaces. */
  expanded?: boolean;
  /** Expand command callback. Used by disclosure-tree keyboard patterns. */
  onExpand?: (event: Event) => void;
  /** Collapse command callback. Used by disclosure-tree keyboard patterns. */
  onCollapse?: (event: Event) => void;
  /** Lift edge declarations for this source surface. */
  lift?: LiftEdges;
  /** Ambient lift manager provided by the environment surface. */
  liftManager?: LiftManager;
  /** Product data/context forwarded to the CardDef/FieldDef lift resolver. */
  liftData?: unknown;
  /** Current active lift source id, used to rerun this modifier for ARIA updates. */
  liftActiveSourceId?: string;
  /** Current active lift target id, used for source-to-lift ARIA relationships. */
  liftActiveTargetId?: string;
  /** Current active lift kind, used for source-to-lift ARIA relationships. */
  liftActiveKind?: string;
}

function isNativeFocusable(element: HTMLElement): boolean {
  return element.matches(
    'button, a[href], input, textarea, select, [contenteditable]:not([contenteditable=false])',
  );
}

function ariaDerivedTarget(element: HTMLElement): Target | undefined {
  const role = element.getAttribute('role')?.trim().toLowerCase();
  if (role) {
    if (actionRoles.has(role)) return 'action';
    if (fieldRoles.has(role)) return 'field';
    if (rangeItemRoles.has(role)) return 'range-item';
    if (objectRoles.has(role)) return 'object';
    if (chromeRoles.has(role)) return 'chrome';
    if (role === 'group' || role === 'presentation' || role === 'none') {
      return 'structure';
    }
  }

  switch (element.localName) {
    case 'a':
    case 'button':
      return 'action';
    case 'input':
    case 'select':
    case 'textarea':
      return 'field';
    case 'article':
    case 'figure':
    case 'img':
      return 'object';
    case 'aside':
    case 'footer':
    case 'header':
    case 'nav':
      return 'chrome';
    case 'td':
    case 'th':
    case 'li':
      return 'range-item';
    case 'section':
      return element.hasAttribute('aria-label') ||
        element.hasAttribute('aria-labelledby')
        ? 'object'
        : 'structure';
    default:
      return undefined;
  }
}

function isTextEntryElement(element: Element | null): element is HTMLElement {
  if (!element) return false;
  return (
    isSurfaceTextEntryTarget(element) ||
    surfaceTargetRetainsBrowserFocusAfterSelection(element) ||
    element.matches('select')
  );
}

function shouldDeselectBareSurfaceBackground(
  surface: LadderSurface | undefined,
  element: HTMLElement,
  target: Element | null,
): boolean {
  if (target !== element) return false;

  const override = element.getAttribute('data-surface-background');
  if (override === 'select') return false;
  if (override === 'deselect') return true;

  return surface !== undefined && backgroundDeselectSurfaces.has(surface);
}

function shouldPreserveSurfaceFocus(target: Element | null): boolean {
  return surfaceTargetRetainsBrowserFocusAfterSelection(target);
}

function textEntryElements(element: HTMLElement): HTMLElement[] {
  return Array.from(
    element.querySelectorAll<HTMLElement>(
      'input, textarea, select, [contenteditable]:not([contenteditable=false])',
    ),
  ).filter(isTextEntryElement);
}

function isMagneticSelectionUnit(opts: NodeOptions): boolean {
  return (
    opts.surface === 'cell' && opts.policy?.pointer !== 'content-interactive'
  );
}

function snapFocusToMagneticSelectionUnit(
  element: HTMLElement,
  target: Element | null,
  opts: NodeOptions,
): void {
  if (!isMagneticSelectionUnit(opts)) return;
  if (target === element) return;
  if (surfaceTargetRetainsBrowserFocusAfterSelection(target)) return;

  const hit = target?.closest('[data-ladder-id]');
  if (hit !== element) return;

  const focusElement = (): void => {
    if (!element.isConnected) return;
    if (element.ownerDocument.activeElement === element) return;
    element.focus({ preventScroll: true });
  };

  requestAnimationFrame(focusElement);
  setTimeout(focusElement, 0);
}

function shouldDelegateToEditor(
  surface: LadderSurface | undefined,
  element: HTMLElement,
  target: Element | null,
): boolean {
  if (isTextEntryElement(target)) return true;
  let editorCount = textEntryElements(element).length;
  if (surface === 'cell') return editorCount > 0;
  return editorCount === 1;
}

function focusSurfaceEditor(
  element: HTMLElement,
  target: Element | null,
  requireSingleEditor: boolean,
): void {
  const editor = isTextEntryElement(target)
    ? target
    : (() => {
        let editors = textEntryElements(element);
        if (requireSingleEditor && editors.length !== 1) return null;
        return editors[0] ?? null;
      })();
  if (!editor) return;

  editor.focus({ preventScroll: true });
  requestAnimationFrame(() => {
    if (!editor.isConnected) return;
    editor.focus({ preventScroll: true });
  });
  setTimeout(() => {
    if (!editor.isConnected) return;
    editor.focus({ preventScroll: true });
  }, 0);
}

function isSurfaceNodeMode(value: string | null): value is SurfaceNodeMode {
  return value === 'use' || value === 'change' || value === 'inspect';
}

function isEnabledDataAttribute(value: string | null): boolean {
  return value === '' || value === 'true';
}

function modeForElement(
  element: HTMLElement,
  mode: SurfaceNodeMode | undefined,
): SurfaceNodeMode {
  if (mode) return mode;
  const modeRoot = element.closest<HTMLElement>('[data-surface-mode]');
  const inherited = modeRoot?.getAttribute('data-surface-mode') ?? null;
  return isSurfaceNodeMode(inherited) ? inherited : 'use';
}

function inspectForElement(
  element: HTMLElement,
  inspect: boolean | undefined,
): boolean {
  if (inspect !== undefined) return inspect;
  const inspectRoot = element.closest<HTMLElement>('[data-surface-inspect]');
  const inherited = inspectRoot?.getAttribute('data-surface-inspect') ?? null;
  if (isEnabledDataAttribute(inherited)) return true;
  if (inherited === 'false') return false;
  return modeForElement(element, undefined) === 'inspect';
}

function selectionModeForElement(
  element: HTMLElement,
  opts: NodeOptions,
): SurfaceNodeMode {
  const mode = modeForElement(element, opts.mode);
  if (mode === 'use' && inspectForElement(element, opts.inspect)) {
    return 'inspect';
  }
  return mode;
}

function runtimeForNode(
  element: HTMLElement,
  opts: NodeOptions,
): SurfaceRuntime | undefined {
  return opts.runtime ?? surfaceRuntimeForElement(element);
}

function runtimeClickOptionsForElement(
  element: HTMLElement,
  opts: NodeOptions,
): { mode: SurfaceNodeMode; inspect: boolean } {
  return {
    mode: selectionModeForElement(element, opts),
    inspect: inspectForElement(element, opts.inspect),
  };
}

function semanticPathForEvent(event: Event): string[] {
  const ids: string[] = [];
  const seen = new Set<string>();
  for (const target of event.composedPath()) {
    if (!(target instanceof Element)) continue;
    const id = target.getAttribute('data-ladder-id');
    if (!id || seen.has(id)) continue;
    seen.add(id);
    ids.push(id);
  }
  return ids;
}

function projectedClickTargetId(
  owningLadder: FocusLadder,
  element: HTMLElement,
  opts: NodeOptions,
  rawTargetId: string | null,
  pointerPath: readonly string[],
): string | null {
  if (!rawTargetId) return null;

  const runtime = runtimeForNode(element, opts);
  if (runtime) {
    const traversalIds = new Set(
      runtime.traversalSet(runtimeClickOptionsForElement(element, opts)).ids,
    );
    for (const id of pointerPath) {
      if (traversalIds.has(id)) return id;
    }
    return runtime.node(rawTargetId) ? rawTargetId : null;
  }

  return owningLadder.targetIdFor(
    rawTargetId,
    selectionModeForElement(element, opts),
  );
}

function resolvedClickTargetId(
  owningLadder: FocusLadder,
  element: HTMLElement,
  opts: NodeOptions,
  rawTargetId: string | null,
  event: MouseEvent,
  pointerPath: readonly string[],
): { targetId: string | null; handledByRuntime: boolean } {
  if (!rawTargetId) return { targetId: null, handledByRuntime: false };

  const runtime = runtimeForNode(element, opts);
  if (runtime) {
    const result = runtime.dispatch({
      type: 'click',
      targetId: rawTargetId,
      detail: event.detail,
      additive: event.metaKey || event.ctrlKey,
      range: event.shiftKey,
      pointerPath,
      ...runtimeClickOptionsForElement(element, opts),
    });
    return {
      targetId: result.ownerId,
      handledByRuntime: result.handled,
    };
  }

  return {
    targetId: owningLadder.targetIdFor(
      rawTargetId,
      selectionModeForElement(element, opts),
    ),
    handledByRuntime: false,
  };
}

function isUseInteractiveTarget(
  target: Target | undefined,
  opts: NodeOptions,
): boolean {
  return (
    target === 'action' ||
    opts.onActivate !== undefined ||
    opts.onExpand !== undefined ||
    opts.onCollapse !== undefined ||
    opts.scrollOnSelect === true ||
    opts.hoverSignal !== undefined
  );
}

function encodePathPart(part: SurfacePathPart): string {
  return encodeURIComponent(String(part));
}

interface ParentSurfaceCoordinate {
  state: 'none' | 'pending' | 'ready';
  path?: string;
}

function parentSurfaceForElement(element: HTMLElement): HTMLElement | null {
  return (
    element.parentElement?.closest<HTMLElement>('[data-surface-component]') ??
    null
  );
}

function parentSurfaceCoordinateForElement(
  element: HTMLElement,
): ParentSurfaceCoordinate {
  const parentSurface = parentSurfaceForElement(element);
  if (!parentSurface) return { state: 'none' };
  if (parentSurface.getAttribute('data-surface-coordinate-ready') !== 'true') {
    return { state: 'pending' };
  }

  const path =
    parentSurface.getAttribute('data-surface-coordinate') ??
    parentSurface.getAttribute('data-surface-path') ??
    null;
  return path ? { state: 'ready', path } : { state: 'none' };
}

function parentSurfacePathForElement(element: HTMLElement): string | null {
  const parentSurface = element.parentElement?.closest<HTMLElement>(
    '[data-surface-coordinate], [data-surface-path]',
  );
  return (
    parentSurface?.getAttribute('data-surface-coordinate') ??
    parentSurface?.getAttribute('data-surface-path') ??
    null
  );
}

function appendPath(parentPath: string, keyParts: SurfacePathPart[]): string {
  const suffix = keyParts.map(encodePathPart).join(':');
  return suffix ? `${parentPath}:${suffix}` : parentPath;
}

interface RuntimeCoordinateSpace {
  coordinate: string;
  id: string;
  schema: string;
}

function nearestCoordinateSpaceElement(
  element: HTMLElement,
): HTMLElement | null {
  return (
    element.parentElement?.closest<HTMLElement>(
      '[data-surface-coordinate-space][data-surface-coordinate-space-id]',
    ) ?? null
  );
}

function coordinateSpaceForElement(
  element: HTMLElement,
  opts: NodeOptions,
  parentCoordinate = parentSurfaceCoordinateForElement(element),
): RuntimeCoordinateSpace | undefined {
  const local = opts.localCoordinate;

  if (opts.coordinateSpace) {
    const spaceId = opts.focusKey ?? opts.id;
    if (!spaceId) return undefined;
    const parentSpace = local ? nearestCoordinateSpaceElement(element) : null;
    const parentSpaceId = parentSpace?.getAttribute(
      'data-surface-coordinate-space-id',
    );
    const parentSchema = parentSpace?.getAttribute(
      'data-surface-coordinate-space',
    );
    const coordinate =
      local && parentSpaceId && parentSchema
        ? `${parentSpaceId}[${parentSchema}]:${local}`
        : (opts.coordinate ??
          (local
            ? `${spaceId}[${opts.coordinateSpace}]:${local}`
            : `${spaceId}[${opts.coordinateSpace}]`));
    return {
      coordinate,
      id: spaceId,
      schema: opts.coordinateSpace,
    };
  }

  if (!local) return undefined;
  const parentSpace = nearestCoordinateSpaceElement(element);
  const parentSpaceId = parentSpace?.getAttribute(
    'data-surface-coordinate-space-id',
  );
  const parentSchema = parentSpace?.getAttribute(
    'data-surface-coordinate-space',
  );
  if (!parentSpaceId || !parentSchema) return undefined;

  if (parentCoordinate.path) {
    return {
      coordinate: appendPath(parentCoordinate.path, [local]),
      id: parentSpaceId,
      schema: parentSchema,
    };
  }

  return {
    coordinate: `${parentSpaceId}[${parentSchema}]:${local}`,
    id: parentSpaceId,
    schema: parentSchema,
  };
}

function shouldRefineCoordinateFromDom(
  source: SurfaceCoordinateSource | undefined,
): boolean {
  return source === 'context' || source === 'generated';
}

function surfaceCoordinateForElement(
  element: HTMLElement,
  opts: NodeOptions,
  parentCoordinate = parentSurfaceCoordinateForElement(element),
): string | undefined {
  const inheritedPath =
    parentCoordinate.path ?? parentSurfacePathForElement(element);
  const domCoordinate = inheritedPath
    ? appendPath(inheritedPath, opts.keyParts ?? [])
    : undefined;

  if (shouldRefineCoordinateFromDom(opts.coordinateSource) && domCoordinate) {
    return domCoordinate;
  }

  return (
    opts.coordinate ??
    opts.focusKey ??
    (opts.generatedId ? domCoordinate : undefined)
  );
}

let hoveredSurface: HTMLElement | null = null;
const hoverSignalByRoot = new WeakMap<HTMLElement, string>();

function clearHoveredSurface(): void {
  hoveredSurface?.classList.remove('is-surface-hovered');
  hoveredSurface = null;
}

function setHoveredSurface(surface: HTMLElement | null): void {
  if (surface === hoveredSurface) return;
  clearHoveredSurface();
  hoveredSurface = surface;
  hoveredSurface?.classList.add('is-surface-hovered');
}

function rootForSurfaceElement(element: HTMLElement): HTMLElement {
  return (
    element.closest<HTMLElement>('[data-surface-component="environment"]') ??
    document.body
  );
}

function clearRootHoverSignal(root: HTMLElement, signal?: string): void {
  const currentSignal = hoverSignalByRoot.get(root);
  if (signal && currentSignal && currentSignal !== signal) return;

  for (const target of root.querySelectorAll<HTMLElement>(
    '.is-surface-correspondence-hovered',
  )) {
    target.classList.remove('is-surface-correspondence-hovered');
  }
  hoverSignalByRoot.delete(root);
}

function setRootHoverSignal(root: HTMLElement, signal: string): void {
  if (hoverSignalByRoot.get(root) === signal) return;
  clearRootHoverSignal(root);
  for (const target of root.querySelectorAll<HTMLElement>(
    '[data-surface-hover-anchor]',
  )) {
    if (target.getAttribute('data-surface-hover-anchor') === signal) {
      target.classList.add('is-surface-correspondence-hovered');
    }
  }
  hoverSignalByRoot.set(root, signal);
}

function surfaceIdForElement(element: HTMLElement | null): string | null {
  return element?.getAttribute('data-ladder-id') ?? null;
}

function surfaceElementById(
  root: HTMLElement,
  id: string | null,
): HTMLElement | null {
  if (!id) return null;
  if (root.getAttribute('data-ladder-id') === id) return root;
  for (const element of root.querySelectorAll<HTMLElement>(
    '[data-ladder-id]',
  )) {
    if (element.getAttribute('data-ladder-id') === id) return element;
  }
  return null;
}

function nearestSurfaceAtPoint(
  root: HTMLElement,
  event: MouseEvent,
): HTMLElement | null {
  for (const element of document.elementsFromPoint(
    event.clientX,
    event.clientY,
  )) {
    const surface = element.closest<HTMLElement>('[data-ladder-id]');
    if (surface && root.contains(surface)) return surface;
  }

  const target = event.target as Element | null;
  const fallback = target?.closest<HTMLElement>('[data-ladder-id]') ?? null;
  return fallback && root.contains(fallback) ? fallback : null;
}

function nearestLiftSourceForTarget(
  root: HTMLElement,
  target: Element | null,
): HTMLElement | null {
  const source =
    target?.closest<HTMLElement>('[data-surface-lift-source]') ?? null;
  return source && root.contains(source) ? source : null;
}

function nearestLiftSourceAtPoint(
  root: HTMLElement,
  event: MouseEvent,
): HTMLElement | null {
  for (const element of document.elementsFromPoint(
    event.clientX,
    event.clientY,
  )) {
    const source = element.closest<HTMLElement>('[data-surface-lift-source]');
    if (source && root.contains(source)) return source;
  }

  return nearestLiftSourceForTarget(root, event.target as Element | null);
}

function hasLiftEdges(edges: LiftEdges | undefined): boolean {
  return edges !== undefined && Object.values(edges).some(Boolean);
}

const surfaceNode = modifier<{
  Element: HTMLElement;
  Args: { Positional: [FocusLadder | undefined]; Named: NodeOptions };
}>((element, [ladder], opts = {}) => {
  const priorLadderId = element.getAttribute('data-ladder-id');
  const priorFocusKey = element.getAttribute('data-surface-focus-key');
  const priorSurfacePath = element.getAttribute('data-surface-path');
  const priorSurfaceCoordinate = element.getAttribute(
    'data-surface-coordinate',
  );
  const priorSurfaceCoordinateReady = element.getAttribute(
    'data-surface-coordinate-ready',
  );
  const priorSurface = element.getAttribute('data-surface');
  const priorSurfaceTarget = element.getAttribute('data-surface-target');
  const priorSurfaceTargetScope = element.getAttribute(
    'data-surface-target-scope',
  );
  const priorTabindex = element.getAttribute('tabindex');
  const priorId = element.getAttribute('id');
  const priorAriaExpanded = element.getAttribute('aria-expanded');
  const priorAriaControls = element.getAttribute('aria-controls');
  const priorAriaDescribedBy = element.getAttribute('aria-describedby');
  const priorAriaHasPopup = element.getAttribute('aria-haspopup');
  const priorLiftSource = element.getAttribute('data-surface-lift-source');
  const priorScrollAnchor = element.getAttribute('data-surface-scroll-anchor');
  const priorScrollTarget = element.getAttribute('data-surface-scroll-target');
  const priorHoverAnchor = element.getAttribute('data-surface-hover-anchor');
  const priorHoverSignal = element.getAttribute('data-surface-hover-signal');
  const priorSurfaceActivatable = element.getAttribute(
    'data-surface-activatable',
  );
  const priorSurfaceExpandable = element.getAttribute(
    'data-surface-expandable',
  );
  const priorSurfaceExpanded = element.getAttribute('data-surface-expanded');
  const priorSurfaceDecalShape = element.getAttribute(
    'data-surface-decal-shape',
  );

  let cleanup = (): void => {};
  let didInstall = false;
  let isDestroying = false;
  let restoreFocusTimer: ReturnType<typeof setTimeout> | undefined;
  let installRetryFrame: number | undefined;
  let installRetryCount = 0;

  const install = (): boolean => {
    if (isDestroying || didInstall) return didInstall;
    const owningLadder = ladder ?? ladderForSurfaceElement(element);
    if (!owningLadder || !opts.id || !opts.surface) return false;
    const parentCoordinate = parentSurfaceCoordinateForElement(element);
    if (parentCoordinate.state === 'pending') {
      return false;
    }

    const ownLiftManager = (): LiftManager | undefined =>
      opts.liftManager ?? liftManagerForSurfaceElement(element);

    const runtimeCoordinateSpace = coordinateSpaceForElement(
      element,
      opts,
      parentCoordinate,
    );
    const runtimeCoordinate =
      runtimeCoordinateSpace?.coordinate ??
      surfaceCoordinateForElement(element, opts, parentCoordinate);
    const nodeId = runtimeCoordinate
      ? `${opts.surface}:${runtimeCoordinate}`
      : opts.id;
    if (!nodeId) return false;
    const unregisterLiftRoot = opts.liftManager
      ? registerSurfaceLiftDomRoot(element, opts.liftManager)
      : undefined;

    element.setAttribute('id', nodeId);
    element.setAttribute('data-ladder-id', nodeId);
    if (runtimeCoordinate) {
      element.setAttribute('data-surface-coordinate', runtimeCoordinate);
      element.setAttribute('data-surface-focus-key', runtimeCoordinate);
      element.setAttribute('data-surface-path', runtimeCoordinate);
    }
    if (runtimeCoordinateSpace) {
      element.setAttribute(
        'data-surface-coordinate-space',
        runtimeCoordinateSpace.schema,
      );
      element.setAttribute(
        'data-surface-coordinate-space-id',
        runtimeCoordinateSpace.id,
      );
      if (opts.localCoordinate) {
        element.setAttribute(
          'data-surface-local-coordinate',
          opts.localCoordinate,
        );
      }
    }
    element.setAttribute('data-surface-coordinate-ready', 'true');
    element.setAttribute('data-surface', opts.surface);
    const target = opts.target ?? ariaDerivedTarget(element);
    if (target) {
      element.setAttribute('data-surface-target', target);
    } else {
      element.removeAttribute('data-surface-target');
    }
    if (opts.targetScope) {
      element.setAttribute('data-surface-target-scope', opts.targetScope);
    } else {
      element.removeAttribute('data-surface-target-scope');
    }
    if (hasLiftEdges(opts.lift)) {
      element.setAttribute('data-surface-lift-source', nodeId);
    } else {
      element.removeAttribute('data-surface-lift-source');
    }
    if (opts.policy?.decalShape) {
      element.setAttribute('data-surface-decal-shape', opts.policy.decalShape);
    } else {
      element.removeAttribute('data-surface-decal-shape');
    }
    const scrollAnchor = opts.scrollAnchor ?? runtimeCoordinate;
    if (scrollAnchor) {
      element.setAttribute('data-surface-scroll-anchor', scrollAnchor);
    } else {
      element.removeAttribute('data-surface-scroll-anchor');
    }
    const scrollTarget = opts.scrollTarget ?? runtimeCoordinate;
    if (opts.scrollOnSelect && scrollTarget) {
      element.setAttribute('data-surface-scroll-target', scrollTarget);
    } else {
      element.removeAttribute('data-surface-scroll-target');
    }
    const hoverAnchor = opts.hoverAnchor ?? runtimeCoordinate;
    if (hoverAnchor) {
      element.setAttribute('data-surface-hover-anchor', hoverAnchor);
    } else {
      element.removeAttribute('data-surface-hover-anchor');
    }
    if (opts.hoverSignal) {
      element.setAttribute('data-surface-hover-signal', opts.hoverSignal);
    } else {
      element.removeAttribute('data-surface-hover-signal');
    }
    if (opts.onActivate) {
      element.setAttribute('data-surface-activatable', 'true');
    } else {
      element.removeAttribute('data-surface-activatable');
    }

    const hasDisclosure = opts.expanded !== undefined;
    if (hasDisclosure) {
      element.setAttribute('data-surface-expandable', 'true');
      element.setAttribute(
        'data-surface-expanded',
        String(opts.expanded ?? false),
      );
    } else {
      element.removeAttribute('data-surface-expandable');
      element.removeAttribute('data-surface-expanded');
    }

    const domParentId = parentSurfaceIdForElement(element);
    const parentId = domParentId ?? opts.parentId ?? null;

    const sourceForLift = (): LiftSource => ({
      id: nodeId,
      path: runtimeCoordinate ?? opts.focusKey,
      surface: opts.surface!,
      element,
      data: opts.liftData,
    });
    const unregisterLiftSource = hasLiftEdges(opts.lift)
      ? ownLiftManager()?.registerSource(sourceForLift(), opts.lift)
      : undefined;

    const syncLiftAria = (): void => {
      const isActiveLiftSource =
        opts.liftActiveSourceId !== undefined &&
        opts.liftActiveSourceId === nodeId &&
        opts.liftActiveTargetId !== undefined;

      if (!isActiveLiftSource) {
        if (hasDisclosure) {
          element.setAttribute('aria-expanded', String(opts.expanded ?? false));
        } else {
          element.removeAttribute('aria-expanded');
        }
        element.removeAttribute('aria-controls');
        element.removeAttribute('aria-describedby');
        element.removeAttribute('aria-haspopup');
        return;
      }

      const kind = opts.liftActiveKind;
      const targetId = opts.liftActiveTargetId!;

      if (kind === 'details') {
        element.setAttribute('aria-describedby', targetId);
        element.removeAttribute('aria-haspopup');
        element.removeAttribute('aria-controls');
      } else {
        element.setAttribute('aria-controls', targetId);
        element.removeAttribute('aria-describedby');
        if (kind === 'edit' || kind === 'preview') {
          element.setAttribute('aria-haspopup', 'dialog');
        } else if (kind === 'tools') {
          element.setAttribute('aria-haspopup', 'menu');
        }
      }
      element.setAttribute('aria-expanded', 'true');
    };

    syncLiftAria();
    ownLiftManager()?.updateSourceData(nodeId, opts.liftData);

    const registration: FociNodeRegistration = {
      id: nodeId,
      focusKey: runtimeCoordinate,
      surface: opts.surface,
      target,
      targetScope: opts.targetScope,
      scopeId: opts.scopeId,
      scopeKind: opts.scopeKind,
      policy: opts.policy,
      grid: opts.grid,
      coordinateSpaceId: runtimeCoordinateSpace?.id,
      localCoordinate: opts.localCoordinate,
      parentId,
    };
    const owningRuntime = runtimeForNode(element, opts);
    const unregister = owningLadder.register(registration);
    const unregisterDomNode = owningRuntime
      ? registerSurfaceDomNode(owningRuntime, nodeId, element)
      : undefined;
    const unregisterRuntime = owningRuntime?.register(registration);
    const invokeSelect = (event: Event): void => {
      opts.onSelect?.(event);
      if (!opts.scrollOnSelect) return;
      const targetKey = opts.scrollTarget ?? runtimeCoordinate;
      if (!targetKey) return;
      const root =
        element.closest<HTMLElement>(
          '[data-surface-component="environment"]',
        ) ?? document.body;
      const target = Array.from(
        root.querySelectorAll<HTMLElement>('[data-surface-scroll-anchor]'),
      ).find(
        (candidate) =>
          candidate.getAttribute('data-surface-scroll-anchor') === targetKey,
      );
      target?.scrollIntoView({
        block: 'center',
        inline: 'nearest',
        behavior: 'auto',
      });
    };
    const invokeActivate = (event: Event): boolean => {
      if (!opts.onActivate) return false;
      event.preventDefault();
      event.stopPropagation();
      opts.onActivate(event);
      return true;
    };
    const invokeExpand = (event: Event): boolean => {
      if (!opts.onExpand) return false;
      event.preventDefault();
      event.stopPropagation();
      opts.onExpand(event);
      return true;
    };
    const invokeCollapse = (event: Event): boolean => {
      if (!opts.onCollapse) return false;
      event.preventDefault();
      event.stopPropagation();
      opts.onCollapse(event);
      return true;
    };
    const onSurfaceActivate = (event: Event): void => {
      invokeActivate(event);
    };
    const onSurfaceExpand = (event: Event): void => {
      invokeExpand(event);
    };
    const onSurfaceCollapse = (event: Event): void => {
      invokeCollapse(event);
    };
    const onFocus = (event: FocusEvent): void => {
      if (event.target !== element) return;
      invokeSelect(event);
    };
    const scheduleHoverId = (id: string | null): void => {
      setTimeout(() => {
        if (!isDestroying) owningLadder.hoverId(id);
      }, 0);
    };
    const applyHoverSignal = (active: boolean): void => {
      if (!opts.hoverSignal) return;
      const root = rootForSurfaceElement(element);
      if (active) setRootHoverSignal(root, opts.hoverSignal);
      else clearRootHoverSignal(root, opts.hoverSignal);
    };
    const clearInspectHover = (): void => {
      const root = rootForSurfaceElement(element);
      clearRootHoverSignal(root);
      if (hoveredSurface && root.contains(hoveredSurface)) {
        clearHoveredSurface();
      }
      scheduleHoverId(null);
    };
    const onClick = (event: MouseEvent): void => {
      if (opts.skipClick) return;
      const target = event.target as Element | null;
      if (shouldPreserveSurfaceFocus(target)) return;
      const pointerPath = semanticPathForEvent(event);
      const rawTargetId = pointerPath[0] ?? null;
      const hit = target?.closest('[data-ladder-id]');
      const liftHit = nearestLiftSourceForTarget(element, target);
      const hitTargetId =
        hit instanceof HTMLElement
          ? projectedClickTargetId(
              owningLadder,
              element,
              opts,
              rawTargetId ?? surfaceIdForElement(hit),
              pointerPath,
            )
          : null;
      const isDirectSurfaceHit = hit === element;
      const isLiftSourceHit = liftHit === element;
      const isResolvedSurfaceHit = hitTargetId === nodeId;
      if (
        isDirectSurfaceHit &&
        shouldDeselectBareSurfaceBackground(opts.surface, element, target)
      ) {
        return;
      }
      if (
        isLiftSourceHit &&
        !isDirectSurfaceHit &&
        hit instanceof HTMLElement
      ) {
        if (hitTargetId && hitTargetId !== nodeId) return;
      }
      if (!isDirectSurfaceHit && !isLiftSourceHit && !isResolvedSurfaceHit) {
        return;
      }
      const resolved = resolvedClickTargetId(
        owningLadder,
        element,
        opts,
        rawTargetId ?? nodeId,
        event,
        pointerPath,
      );
      const targetId = resolved.targetId;
      if (targetId && !resolved.handledByRuntime)
        owningLadder.focusId(targetId);
      if (!isNativeFocusable(element)) {
        invokeSelect(event);
      }
      const shouldDelegateEditor =
        isDirectSurfaceHit &&
        modeForElement(element, opts.mode) === 'change' &&
        shouldDelegateToEditor(opts.surface, element, target);
      if (shouldDelegateEditor) {
        focusSurfaceEditor(element, target, opts.surface !== 'cell');
      } else {
        snapFocusToMagneticSelectionUnit(element, target, opts);
      }
    };
    const onPointerDown = (event: PointerEvent): void => {
      const target = event.target as Element | null;
      if (shouldPreserveSurfaceFocus(target)) return;
      const hit = target?.closest('[data-ladder-id]');
      if (hit !== element) return;
      if (
        modeForElement(element, opts.mode) === 'change' &&
        shouldDelegateToEditor(opts.surface, element, target)
      ) {
        focusSurfaceEditor(element, target, opts.surface !== 'cell');
      }
    };
    const onDoubleClick = (event: MouseEvent): void => {
      const target = event.target as Element | null;
      if (shouldPreserveSurfaceFocus(target)) return;
      if (isTextEntryElement(target)) return;
      const hit = target?.closest('[data-ladder-id]');
      const liftHit = nearestLiftSourceForTarget(element, target);
      const activationHit = target?.closest(
        '[data-surface-activatable="true"]',
      );
      const isDirectSurfaceHit = hit === element;
      const isLiftSourceHit = liftHit === element;
      const isActivationHit = activationHit === element;
      if (
        isLiftSourceHit &&
        !isDirectSurfaceHit &&
        hit instanceof HTMLElement
      ) {
        const hitTargetId = owningLadder.targetIdFor(
          surfaceIdForElement(hit),
          selectionModeForElement(element, opts),
        );
        if (hitTargetId && hitTargetId !== nodeId) return;
      }
      if (!isDirectSurfaceHit && !isLiftSourceHit && !isActivationHit) return;
      if (isLiftSourceHit || isActivationHit) {
        const targetId = owningLadder.targetIdFor(
          nodeId,
          selectionModeForElement(element, opts),
        );
        if (targetId) owningLadder.focusId(targetId);
      }
      if (isActivationHit && invokeActivate(event)) return;
      if (
        isDirectSurfaceHit &&
        modeForElement(element, opts.mode) === 'change' &&
        shouldDelegateToEditor(opts.surface, element, target)
      ) {
        focusSurfaceEditor(element, target, opts.surface !== 'cell');
        return;
      }
      ownLiftManager()?.openForMode(
        sourceForLift(),
        opts.lift,
        modeForElement(element, opts.mode),
        'change-activate',
      );
    };
    const onInspectHover = (event: MouseEvent): void => {
      const target = event.target as Element | null;
      if (
        isTextEntryElement(target) ||
        isTextEntryElement(document.activeElement)
      ) {
        clearInspectHover();
        return;
      }

      applyHoverSignal(true);
      if (!inspectForElement(element, opts.inspect)) {
        const root = rootForSurfaceElement(element);
        if (hoveredSurface && root.contains(hoveredSurface)) {
          clearHoveredSurface();
        }
        scheduleHoverId(null);
        ownLiftManager()?.scheduleDismissDetails();
        return;
      }

      const liftSource = nearestLiftSourceAtPoint(element, event);
      const surface = liftSource ?? nearestSurfaceAtPoint(element, event);
      const targetId = owningLadder.targetIdFor(
        surfaceIdForElement(surface),
        'inspect',
      );
      const targetSurface = surfaceElementById(element, targetId);
      setHoveredSurface(targetSurface);
      scheduleHoverId(targetId);
      if (liftSource === element) {
        ownLiftManager()?.scheduleHover(sourceForLift(), opts.lift, 'inspect');
      }
    };
    const onInspectLeave = (event: MouseEvent): void => {
      const relatedTarget = event.relatedTarget as Element | null;
      if (relatedTarget && element.contains(relatedTarget)) return;
      requestAnimationFrame(() => {
        if (isDestroying || element.matches(':hover')) return;
        applyHoverSignal(false);
        if (hoveredSurface && element.contains(hoveredSurface)) {
          clearHoveredSurface();
        }
        scheduleHoverId(null);
        ownLiftManager()?.scheduleDismissDetails();
      });
    };
    let didInstallClick = false;
    let didInstallPointerDown = false;
    let didInstallHover = false;

    const updateInteractivity = (): void => {
      const nextMode = modeForElement(element, opts.mode);
      const inspectEnabled = inspectForElement(element, opts.inspect);
      const useInteractive = isUseInteractiveTarget(target, opts);
      if (priorTabindex === null && !isNativeFocusable(element)) {
        if (nextMode === 'use' && !inspectEnabled && !useInteractive) {
          element.removeAttribute('tabindex');
        } else {
          element.setAttribute('tabindex', '0');
        }
      }

      if (nextMode === 'use' && !inspectEnabled && !useInteractive) {
        if (didInstallClick) {
          element.removeEventListener('click', onClick);
          element.removeEventListener('dblclick', onDoubleClick);
          didInstallClick = false;
        }
        if (didInstallPointerDown) {
          element.removeEventListener('pointerdown', onPointerDown);
          didInstallPointerDown = false;
        }
      } else if (!didInstallClick) {
        element.addEventListener('click', onClick);
        element.addEventListener('dblclick', onDoubleClick);
        didInstallClick = true;
      }
      if (nextMode === 'change' && !didInstallPointerDown) {
        element.addEventListener('pointerdown', onPointerDown);
        didInstallPointerDown = true;
      } else if (nextMode !== 'change' && didInstallPointerDown) {
        element.removeEventListener('pointerdown', onPointerDown);
        didInstallPointerDown = false;
      }
      if ((inspectEnabled || opts.hoverSignal) && !didInstallHover) {
        element.addEventListener('pointerover', onInspectHover);
        element.addEventListener('pointermove', onInspectHover);
        element.addEventListener('mouseover', onInspectHover);
        element.addEventListener('mousemove', onInspectHover);
        element.addEventListener('pointerleave', onInspectLeave);
        element.addEventListener('mouseleave', onInspectLeave);
        didInstallHover = true;
      } else if (!inspectEnabled && !opts.hoverSignal && didInstallHover) {
        clearInspectHover();
        element.removeEventListener('pointerover', onInspectHover);
        element.removeEventListener('pointermove', onInspectHover);
        element.removeEventListener('mouseover', onInspectHover);
        element.removeEventListener('mousemove', onInspectHover);
        element.removeEventListener('pointerleave', onInspectLeave);
        element.removeEventListener('mouseleave', onInspectLeave);
        didInstallHover = false;
      }
    };

    updateInteractivity();
    element.addEventListener('surface-activate', onSurfaceActivate);
    element.addEventListener('surface-expand', onSurfaceExpand);
    element.addEventListener('surface-collapse', onSurfaceCollapse);
    element.addEventListener('focus', onFocus);

    const modeRoot = opts.mode
      ? null
      : element.closest<HTMLElement>('[data-surface-mode]');
    const inspectRoot =
      opts.inspect !== undefined
        ? null
        : element.closest<HTMLElement>('[data-surface-inspect]');
    const modeObserver = modeRoot
      ? new MutationObserver(() => updateInteractivity())
      : null;
    modeObserver?.observe(modeRoot!, {
      attributes: true,
      attributeFilter: ['data-surface-mode'],
    });
    const inspectObserver =
      inspectRoot && inspectRoot !== modeRoot
        ? new MutationObserver(() => updateInteractivity())
        : null;
    inspectObserver?.observe(inspectRoot!, {
      attributes: true,
      attributeFilter: ['data-surface-inspect'],
    });

    const paint = (): void => {
      const runtimeProjection = runtimeForNode(element, opts)?.projection({
        mode: selectionModeForElement(element, opts),
      });
      const projected = runtimeProjection?.nodeMap.get(nodeId);
      const surfaceAdornments = new Set(
        projected?.surfaceAdornments ?? projected?.visualAdornments ?? [],
      );
      const isFocused = projected
        ? surfaceAdornments.has('focus')
        : owningLadder.isFocused(nodeId);
      const isSelected = projected
        ? surfaceAdornments.has('selection')
        : owningLadder.isFocused(nodeId);
      const isOnFocusPath = projected
        ? projected.focusPath && !projected.focused && !isFocused
        : owningLadder.isOnFocusPath(nodeId);

      element.classList.toggle('is-surface-focused', isFocused);
      element.classList.toggle('is-surface-selected', isSelected);
      element.classList.toggle(
        'is-surface-focus-path',
        isOnFocusPath && !isFocused,
      );
      element.classList.toggle(
        'is-surface-edit-anchor',
        surfaceAdornments.has('edit-anchor'),
      );
      setDatasetValue(
        element,
        'surfaceVisualAdornments',
        projected?.visualAdornments.join(' ') ?? '',
      );
      setDatasetValue(
        element,
        'surfaceAdornments',
        projected?.surfaceAdornments.join(' ') ?? '',
      );
      setDatasetValue(
        element,
        'surfaceDecalAdornments',
        projected?.decalAdornments.join(' ') ?? '',
      );
      setDatasetValue(
        element,
        'surfaceSuppressedAdornments',
        projected?.suppressedAdornments.join(' ') ?? '',
      );
      setDatasetValue(
        element,
        'surfaceDecalShape',
        projected?.decalShape ?? opts.policy?.decalShape ?? '',
      );

      element.classList.toggle('is-ladder-focused', isFocused);
      element.classList.toggle('is-ladder-selected', isSelected);
    };
    const unsubscribe = owningLadder.subscribe(() => paint());
    const unsubscribeRuntime = owningRuntime?.subscribeSelection(() => paint());
    const shouldRestoreFocus = owningLadder.consumeRestoredFocusId(nodeId);
    const restoreFocus = (): void => {
      if (!isDestroying && element.isConnected) {
        element.focus({ preventScroll: true });
      }
    };
    queueMicrotask(() => {
      if (shouldRestoreFocus) restoreFocus();
      paint();
    });
    if (shouldRestoreFocus) {
      restoreFocusTimer = setTimeout(restoreFocus, 0);
    }

    cleanup = () => {
      if (restoreFocusTimer !== undefined) clearTimeout(restoreFocusTimer);
      unregisterLiftSource?.();
      unregisterLiftRoot?.();
      modeObserver?.disconnect();
      inspectObserver?.disconnect();
      element.removeEventListener('click', onClick);
      element.removeEventListener('dblclick', onDoubleClick);
      element.removeEventListener('pointerdown', onPointerDown);
      element.removeEventListener('surface-activate', onSurfaceActivate);
      element.removeEventListener('surface-expand', onSurfaceExpand);
      element.removeEventListener('surface-collapse', onSurfaceCollapse);
      element.removeEventListener('focus', onFocus);
      element.removeEventListener('pointerover', onInspectHover);
      element.removeEventListener('pointermove', onInspectHover);
      element.removeEventListener('mouseover', onInspectHover);
      element.removeEventListener('mousemove', onInspectHover);
      element.removeEventListener('pointerleave', onInspectLeave);
      element.removeEventListener('mouseleave', onInspectLeave);
      clearInspectHover();
      if (owningLadder.hoveredId === nodeId) {
        setTimeout(() => owningLadder.hoverId(null), 0);
      }
      unsubscribe();
      unsubscribeRuntime?.();
      unregister();
      unregisterDomNode?.();
      unregisterRuntime?.();
      element.classList.remove(
        'is-ladder-focused',
        'is-ladder-selected',
        'is-surface-focused',
        'is-surface-selected',
        'is-surface-focus-path',
        'is-surface-edit-anchor',
      );
      delete element.dataset['surfaceVisualAdornments'];
      delete element.dataset['surfaceAdornments'];
      delete element.dataset['surfaceDecalAdornments'];
      delete element.dataset['surfaceDecalShape'];
      delete element.dataset['surfaceSuppressedAdornments'];
      if (priorLadderId === null) element.removeAttribute('data-ladder-id');
      else element.setAttribute('data-ladder-id', priorLadderId);
      if (priorFocusKey === null)
        element.removeAttribute('data-surface-focus-key');
      else element.setAttribute('data-surface-focus-key', priorFocusKey);
      if (priorSurfacePath === null)
        element.removeAttribute('data-surface-path');
      else element.setAttribute('data-surface-path', priorSurfacePath);
      if (priorSurfaceCoordinate === null)
        element.removeAttribute('data-surface-coordinate');
      else
        element.setAttribute('data-surface-coordinate', priorSurfaceCoordinate);
      if (priorSurfaceCoordinateReady === null)
        element.removeAttribute('data-surface-coordinate-ready');
      else
        element.setAttribute(
          'data-surface-coordinate-ready',
          priorSurfaceCoordinateReady,
        );
      if (priorSurface === null) element.removeAttribute('data-surface');
      else element.setAttribute('data-surface', priorSurface);
      if (priorSurfaceTarget === null)
        element.removeAttribute('data-surface-target');
      else element.setAttribute('data-surface-target', priorSurfaceTarget);
      if (priorSurfaceTargetScope === null)
        element.removeAttribute('data-surface-target-scope');
      else
        element.setAttribute(
          'data-surface-target-scope',
          priorSurfaceTargetScope,
        );
      if (priorTabindex === null) element.removeAttribute('tabindex');
      else element.setAttribute('tabindex', priorTabindex);
      if (priorId === null) element.removeAttribute('id');
      else element.setAttribute('id', priorId);
      if (priorAriaExpanded === null) element.removeAttribute('aria-expanded');
      else element.setAttribute('aria-expanded', priorAriaExpanded);
      if (priorAriaControls === null) element.removeAttribute('aria-controls');
      else element.setAttribute('aria-controls', priorAriaControls);
      if (priorAriaDescribedBy === null)
        element.removeAttribute('aria-describedby');
      else element.setAttribute('aria-describedby', priorAriaDescribedBy);
      if (priorAriaHasPopup === null) element.removeAttribute('aria-haspopup');
      else element.setAttribute('aria-haspopup', priorAriaHasPopup);
      if (priorLiftSource === null)
        element.removeAttribute('data-surface-lift-source');
      else element.setAttribute('data-surface-lift-source', priorLiftSource);
      if (priorScrollAnchor === null)
        element.removeAttribute('data-surface-scroll-anchor');
      else
        element.setAttribute('data-surface-scroll-anchor', priorScrollAnchor);
      if (priorScrollTarget === null)
        element.removeAttribute('data-surface-scroll-target');
      else
        element.setAttribute('data-surface-scroll-target', priorScrollTarget);
      if (priorHoverAnchor === null)
        element.removeAttribute('data-surface-hover-anchor');
      else element.setAttribute('data-surface-hover-anchor', priorHoverAnchor);
      if (priorHoverSignal === null)
        element.removeAttribute('data-surface-hover-signal');
      else element.setAttribute('data-surface-hover-signal', priorHoverSignal);
      if (priorSurfaceActivatable === null)
        element.removeAttribute('data-surface-activatable');
      else
        element.setAttribute(
          'data-surface-activatable',
          priorSurfaceActivatable,
        );
      if (priorSurfaceExpandable === null)
        element.removeAttribute('data-surface-expandable');
      else
        element.setAttribute('data-surface-expandable', priorSurfaceExpandable);
      if (priorSurfaceExpanded === null)
        element.removeAttribute('data-surface-expanded');
      else element.setAttribute('data-surface-expanded', priorSurfaceExpanded);
      if (priorSurfaceDecalShape === null)
        element.removeAttribute('data-surface-decal-shape');
      else
        element.setAttribute(
          'data-surface-decal-shape',
          priorSurfaceDecalShape,
        );
    };
    didInstall = true;
    return true;
  };

  const scheduleInstallRetry = (): void => {
    queueMicrotask(() => {
      if (install()) return;

      const retry = (): void => {
        installRetryFrame = undefined;
        if (isDestroying || install()) return;
        installRetryCount += 1;
        if (installRetryCount < 30) {
          installRetryFrame = requestAnimationFrame(retry);
        }
      };

      installRetryFrame = requestAnimationFrame(retry);
    });
  };

  scheduleInstallRetry();

  return () => {
    isDestroying = true;
    if (installRetryFrame !== undefined)
      cancelAnimationFrame(installRetryFrame);
    queueMicrotask(cleanup);
  };
});

export default surfaceNode;

function setDatasetValue(
  element: HTMLElement,
  key: keyof DOMStringMap,
  value: string,
): void {
  if (element.dataset[key] !== value) {
    element.dataset[key] = value;
  }
}
