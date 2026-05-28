import { modifier } from 'ember-modifier';

import { releaseSurfaceCanvasDomFocus } from '../canvas-dom.ts';
import { surfaceRuntimeForElement } from '../dom-registry.ts';
import {
  isSurfaceTextEntryTarget,
  surfaceElementOwnsKeyboardEvent,
  surfaceTargetOwnsKeyboardEvent,
  surfaceTargetOwnsPointerEvent,
} from '../keyboard.ts';
import { dispatchSurfaceGeometryChange } from '../geometry-events.ts';
import {
  cachedElementList,
  cachedRectForElement,
  createSurfaceDomBindingCache,
  type SurfaceDomBindingCache,
} from './dom-binding-cache.ts';
import type { SurfaceRuntime } from '../surface-runtime.ts';
import type { FociProjectionNode } from '../foci-store.ts';

export {
  clearSurfaceCanvasSelection,
  releaseSurfaceCanvasDomFocus,
  restoreSurfaceCanvasSelection,
} from '../canvas-dom.ts';
export type { SurfaceCanvasDomOptions } from '../canvas-dom.ts';

export interface SurfaceCanvasSelection {
  id: string;
  focusKey?: string;
  kind?: SurfaceCanvasObjectKind;
  field?: string;
  payload?: Record<string, string>;
  index: number;
  x: number;
  y: number;
  width: number;
  height: number;
}

export type SurfaceCanvasObjectKind = 'frame' | 'edge';
export type SurfaceCanvasPointerPhase = 'start' | 'move' | 'end' | 'cancel';

export interface SurfaceCanvasMove {
  phase: SurfaceCanvasPointerPhase;
  dx: number;
  dy: number;
  totalDx: number;
  totalDy: number;
  pointerX: number;
  pointerY: number;
}

export interface SurfaceCanvasResize {
  phase: SurfaceCanvasPointerPhase;
  dx: number;
  dy: number;
  width: number;
  height: number;
  pointerX: number;
  pointerY: number;
}

export type SurfaceCanvasReveal =
  | 'scroll'
  | 'pan'
  | 'none'
  | ((object: HTMLElement, selection: SurfaceCanvasSelection) => void);

export interface SurfaceCanvasSnapPosition {
  x?: number;
  y?: number;
  dx?: number;
  dy?: number;
}

export interface SurfaceCanvasAutoPan {
  dx: number;
  dy: number;
  pointerX: number;
  pointerY: number;
  margin: number;
  phase: SurfaceCanvasPointerPhase;
}

export interface SurfaceCanvasConnection {
  phase: SurfaceCanvasPointerPhase;
  sourceId: string;
  sourceHandleId: string | null;
  sourceHandleType: string | null;
  targetId: string | null;
  targetHandleId: string | null;
  targetHandleType: string | null;
  pointerX: number;
  pointerY: number;
}

export interface SurfaceCanvasMarquee {
  phase: SurfaceCanvasPointerPhase;
  startX: number;
  startY: number;
  currentX: number;
  currentY: number;
  left: number;
  top: number;
  right: number;
  bottom: number;
  width: number;
  height: number;
  pointerX: number;
  pointerY: number;
  ids: string[];
  additive: boolean;
}

export interface SurfaceCanvasBindingOptions {
  active?: boolean;
  runtime?: SurfaceRuntime;
  objectSelector?: string;
  edgeSelector?: string;
  dragHandleSelector?: string;
  pointerDrag?: boolean;
  resizeHandleSelector?: string;
  connectHandleSelector?: string;
  pointerResize?: boolean;
  pointerConnect?: boolean;
  pointerMarquee?: boolean;
  marqueeMinSize?: number;
  autoPan?: boolean;
  autoPanMargin?: number;
  autoPanMaxSpeed?: number;
  reveal?: SurfaceCanvasReveal;
  minResizeWidth?: number;
  minResizeHeight?: number;
  snapPosition?: (
    selection: SurfaceCanvasSelection,
    move: SurfaceCanvasMove,
    event?: PointerEvent | KeyboardEvent,
  ) => SurfaceCanvasSnapPosition | null | undefined;
  onReveal?: (selection: SurfaceCanvasSelection, object: HTMLElement) => void;
  onSelect?: (selection: SurfaceCanvasSelection, event?: Event) => void;
  onActivate?: (selection: SurfaceCanvasSelection, event?: Event) => void;
  onClear?: (event?: Event) => void;
  onDelete?: (selection: SurfaceCanvasSelection, event?: Event) => void;
  onDuplicate?: (selection: SurfaceCanvasSelection, event?: Event) => void;
  onMove?: (
    selection: SurfaceCanvasSelection,
    move: SurfaceCanvasMove,
    event?: PointerEvent,
  ) => void;
  onNudge?: (
    selection: SurfaceCanvasSelection,
    delta: { dx: number; dy: number },
    event?: KeyboardEvent,
  ) => void;
  onResize?: (
    selection: SurfaceCanvasSelection,
    resize: SurfaceCanvasResize,
    event?: PointerEvent,
  ) => void;
  onMarqueeStart?: (
    marquee: SurfaceCanvasMarquee,
    event?: PointerEvent,
  ) => void;
  onMarqueeUpdate?: (
    marquee: SurfaceCanvasMarquee,
    event?: PointerEvent,
  ) => void;
  onMarqueeCommit?: (
    marquee: SurfaceCanvasMarquee,
    event?: PointerEvent,
  ) => void;
  onAutoPan?: (autoPan: SurfaceCanvasAutoPan, event?: PointerEvent) => void;
  onConnectStart?: (
    connection: SurfaceCanvasConnection,
    event?: PointerEvent,
  ) => void;
  onConnectUpdate?: (
    connection: SurfaceCanvasConnection,
    event?: PointerEvent,
  ) => void;
  onConnect?: (
    connection: SurfaceCanvasConnection,
    event?: PointerEvent,
  ) => void;
  onConnectEnd?: (
    connection: SurfaceCanvasConnection,
    event?: PointerEvent,
  ) => void;
  onSelectAll?: (event?: KeyboardEvent) => void;
}

const DEFAULT_OBJECT_SELECTOR =
  '[data-surface-component="frame"][data-canvas-object], [data-canvas-object], [data-surface-canvas-object], [data-surface-scene-object], [data-scene-object]';
const DEFAULT_EDGE_SELECTOR =
  '[data-surface-component="edge"], [data-surface-canvas-edge], .boxel-canvas__edge[data-id]';
const DEFAULT_DRAG_HANDLE_SELECTOR = '[data-surface-canvas-drag-handle]';
const DEFAULT_RESIZE_HANDLE_SELECTOR = '[data-surface-canvas-resize-handle]';
const DEFAULT_CONNECT_HANDLE_SELECTOR =
  '[data-surface-component="handle"], [data-surface-canvas-handle], .boxel-canvas__handle';
const MARQUEE_STYLE_ID = 'boxel-surface-canvas-marquee-styles';

interface ActiveCanvasPointer {
  kind: 'move' | 'resize';
  object: HTMLElement;
  selection: SurfaceCanvasSelection;
  pointerId: number;
  startX: number;
  startY: number;
  initialTransform: string;
  initialWidth: number;
  initialHeight: number;
}

interface ActiveCanvasMarquee {
  pointerId: number;
  startX: number;
  startY: number;
  currentX: number;
  currentY: number;
  additive: boolean;
  overlay: HTMLElement;
}

interface ActiveCanvasConnection {
  pointerId: number;
  sourceId: string;
  sourceHandleId: string | null;
  sourceHandleType: string | null;
  targetId: string | null;
  targetHandleId: string | null;
  targetHandleType: string | null;
}

const CANVAS_KEYS = new Set([
  'ArrowUp',
  'ArrowDown',
  'ArrowLeft',
  'ArrowRight',
  'Tab',
  'Enter',
  'F2',
  'Escape',
  'Delete',
  'Backspace',
  'a',
  'A',
  'd',
  'D',
]);

const surfaceCanvasBinding = modifier<{
  Element: HTMLElement;
  Args: {
    Positional: [];
    Named: SurfaceCanvasBindingOptions;
  };
}>((element, _positional, options) => {
  const view = element.ownerDocument.defaultView ?? window;
  let frame = 0;
  let runtime: SurfaceRuntime | undefined;
  let unsubscribe: (() => void) | undefined;
  let retryCount = 0;
  let hasHydratedSelection = false;
  let cache = createSurfaceDomBindingCache();
  let activePointer: ActiveCanvasPointer | null = null;
  let activeMarquee: ActiveCanvasMarquee | null = null;
  let activeConnection: ActiveCanvasConnection | null = null;
  let previousSelectedIds = new Set<string>();
  let previousTabIndexById = new Map<string, 0 | -1 | null>();
  let previousSelectionPaintRevision = -1;
  let previousBodyUserSelect = '';
  let suppressNextClick = false;

  const schedule = (): void => {
    if (frame !== 0) return;
    frame = view.requestAnimationFrame(paint);
  };

  const invalidate = (): void => {
    cache = createSurfaceDomBindingCache(cache.revision + 1);
  };

  const invalidateAndSchedule = (): void => {
    invalidate();
    schedule();
  };

  const invalidateGeometry = (object: HTMLElement): void => {
    invalidate();
    dispatchSurfaceGeometryChange(object);
  };

  const syncRuntime = (): SurfaceRuntime | undefined => {
    const next = options.runtime ?? surfaceRuntimeForElement(element);
    if (next !== runtime) {
      unsubscribe?.();
      runtime = next;
      unsubscribe = runtime?.subscribeSelection(schedule);
    }
    return runtime;
  };

  const paint = (): void => {
    frame = 0;
    const active = options.active !== false;
    element.dataset['surfaceCanvasBinding'] = active ? 'active' : 'inactive';
    const mode = canvasModeFor(element);
    element.dataset['surfaceCanvasMode'] = mode;
    element.dataset['surfaceCanvasCanMove'] = String(
      mode === 'change' && canvasPointerDragEnabled(options),
    );
    element.dataset['surfaceCanvasCanResize'] = String(
      mode === 'change' && canvasPointerResizeEnabled(options),
    );
    element.dataset['surfaceCanvasCanConnect'] = String(
      mode === 'change' && canvasPointerConnectEnabled(options),
    );
    element.dataset['surfaceCanvasCanMarquee'] = String(
      canvasPointerMarqueeEnabled(options),
    );
    const currentRuntime = syncRuntime();
    if (!active) return;
    if (!currentRuntime) {
      if (retryCount < 120) {
        retryCount += 1;
        schedule();
      }
      return;
    }
    retryCount = 0;

    const projection = currentRuntime.projection({
      mode: canvasModeFor(element),
    });
    let activeId = activeSelectionId(currentRuntime);
    if (activeId) {
      delete element.dataset['surfaceCanvasSelectionCleared'];
      hasHydratedSelection = true;
    }
    if (element.dataset['surfaceCanvasSelectionCleared'] === 'true') {
      hasHydratedSelection = true;
    }
    if (!activeId && !hasHydratedSelection) {
      const seededObject = objects(element, options, cache).find(
        (object) =>
          object.dataset['selected'] === 'true' ||
          object.classList.contains('is-selected') ||
          object.classList.contains('is-runtime-selected'),
      );
      const seededId = seededObject ? surfaceIdFor(seededObject) : null;
      if (seededId) {
        currentRuntime.select(seededId, { restoreSource: true });
        activeId = seededId;
      }
      hasHydratedSelection = true;
    }

    const selectedIds = new Set<string>();
    const objectById = new Map<string, HTMLElement>();
    const objectSelectionState = new Map<string, boolean>();
    const projectionById = new Map<string, FociProjectionNode | undefined>();
    const tabIndexById = new Map<string, 0 | -1 | null>();
    for (const object of objects(element, options, cache)) {
      const id = surfaceIdFor(object);
      const projected = id ? projection.nodeMap.get(id) : undefined;
      const selected = Boolean(
        id && (projected?.selected || projected?.focused || id === activeId),
      );
      if (id) {
        objectById.set(id, object);
        objectSelectionState.set(id, selected);
        projectionById.set(id, projected);
        tabIndexById.set(id, tabIndexForObjectProjection(selected, projected));
        if (selected) selectedIds.add(id);
      } else {
        paintObjectSelectionState(object, selected, projected);
      }
    }

    const forcePaint = previousSelectionPaintRevision !== cache.revision;
    const changedIds = forcePaint
      ? new Set(objectById.keys())
      : symmetricDifference(previousSelectedIds, selectedIds);
    if (!forcePaint) {
      for (const [id, tabIndex] of tabIndexById) {
        if (previousTabIndexById.get(id) !== tabIndex) changedIds.add(id);
      }
    }
    for (const id of changedIds) {
      const object = objectById.get(id);
      if (!object) continue;
      paintObjectSelectionState(
        object,
        objectSelectionState.get(id) ?? false,
        projectionById.get(id),
      );
    }
    previousSelectedIds = selectedIds;
    previousTabIndexById = tabIndexById;
    previousSelectionPaintRevision = cache.revision;
  };

  const selectObject = (
    object: HTMLElement,
    event: Event | undefined,
    opts: { reveal?: boolean; additive?: boolean; range?: boolean } = {},
  ): boolean => {
    if (options.active === false) return false;
    const currentRuntime = syncRuntime();
    const id = surfaceIdFor(object);
    if (!currentRuntime || !id) return false;
    delete element.dataset['surfaceCanvasSelectionCleared'];
    hasHydratedSelection = true;
    currentRuntime.select(id, {
      additive: opts.additive,
      range: opts.range,
      restoreSource: true,
    });
    const selection = selectionForObject(
      element,
      object,
      options,
      cache,
      event,
    );
    focusObject(object, opts.reveal ?? true, selection, options);
    options.onSelect?.(selection, event);
    schedule();
    return true;
  };

  const clearSelection = (event?: Event): boolean => {
    const currentRuntime = syncRuntime();
    if (!currentRuntime) return false;
    const selected = activeSelectionId(currentRuntime);
    if (!selected) return false;
    element.dataset['surfaceCanvasSelectionCleared'] = 'true';
    hasHydratedSelection = true;
    currentRuntime.clearInteractionState();
    releaseSurfaceCanvasDomFocus(element);
    options.onClear?.(event);
    schedule();
    return true;
  };

  const activateObject = (object: HTMLElement, event?: Event): void => {
    selectObject(object, event, { reveal: true });
    syncRuntime()?.dispatch({ type: 'activate' });
    options.onActivate?.(
      selectionForObject(element, object, options, cache, event),
      event,
    );
  };

  const onClick = (event: MouseEvent): void => {
    if (suppressNextClick) {
      suppressNextClick = false;
      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();
      return;
    }
    if (options.active === false) return;
    const target = event.target;
    if (!(target instanceof Element)) return;
    if (target.closest('[data-bx-lift]')) return;
    if (surfaceTargetOwnsPointerEvent(target)) return;

    const object = closestObject(element, target, options);
    if (!object) {
      if (element.contains(target)) clearSelection(event);
      return;
    }
    if (target.closest('[data-surface-activate-frame]')) {
      activateObject(object, event);
      return;
    }
    selectObject(object, event, {
      reveal: false,
      additive: event.metaKey || event.ctrlKey,
      range: event.shiftKey,
    });
  };

  const onPointerDown = (event: PointerEvent): void => {
    if (
      options.active === false ||
      activePointer ||
      activeMarquee ||
      activeConnection
    )
      return;
    if (event.button !== 0) return;
    const target = event.target;
    if (!(target instanceof Element)) return;
    if (target.closest('[data-bx-lift]')) return;
    if (surfaceTargetOwnsPointerEvent(target)) return;

    const mode = canvasModeFor(element);
    if (mode === 'change') {
      const connectHandle = closestConnectHandle(element, target, options);
      if (connectHandle && canvasPointerConnectEnabled(options)) {
        beginConnection(connectHandle, event);
        return;
      }

      const resizeHandle = closestResizeHandle(element, target, options);
      if (resizeHandle && canvasPointerResizeEnabled(options)) {
        const object = closestObject(element, resizeHandle, options);
        if (object && objectKindFor(object, options) !== 'edge') {
          beginPointerResize(object, event);
          return;
        }
      }

      const object = closestObject(element, target, options);
      if (
        object &&
        objectKindFor(object, options) !== 'edge' &&
        canvasPointerDragEnabled(options)
      ) {
        if (!isCanvasDragStartTarget(object, target, options)) return;
        beginPointerMove(object, event);
        return;
      }
      if (object) return;
    } else if (closestObject(element, target, options)) {
      return;
    }

    if (canvasPointerMarqueeEnabled(options) && element.contains(target)) {
      beginMarquee(event);
    }
  };

  const onDblClick = (event: MouseEvent): void => {
    if (options.active === false) return;
    const target = event.target;
    if (!(target instanceof Element)) return;
    if (surfaceTargetOwnsPointerEvent(target)) return;
    const object = closestObject(element, target, options);
    if (!object) return;
    activateObject(object, event);
  };

  const onKeydown = (event: KeyboardEvent): void => {
    if (options.active === false) return;
    if (!CANVAS_KEYS.has(event.key)) return;
    if (event.defaultPrevented) return;
    if (
      event.target instanceof Element &&
      event.target.closest('[data-bx-lift]')
    ) {
      return;
    }
    if (
      surfaceTargetOwnsKeyboardEvent(event) ||
      surfaceElementOwnsKeyboardEvent(
        element.ownerDocument.activeElement,
        event.key,
      )
    ) {
      return;
    }

    const currentRuntime = syncRuntime();
    if (!currentRuntime) return;
    const current =
      activeObjectElement(element, currentRuntime, options, cache) ??
      closestObject(element, element.ownerDocument.activeElement, options);

    if (event.key === 'Escape') {
      if (clearSelection(event)) consume(event);
      return;
    }

    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'a') {
      consume(event);
      options.onSelectAll?.(event);
      return;
    }

    if (event.key === 'Enter' || event.key === 'F2') {
      const object = current ?? objects(element, options, cache)[0];
      if (!object) return;
      consume(event);
      activateObject(object, event);
      return;
    }

    if (event.key === 'Delete' || event.key === 'Backspace') {
      if (!current) return;
      consume(event);
      options.onDelete?.(
        selectionForObject(element, current, options, cache, event),
        event,
      );
      return;
    }

    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'd') {
      if (!current) return;
      consume(event);
      options.onDuplicate?.(
        selectionForObject(element, current, options, cache, event),
        event,
      );
      return;
    }

    if (event.key === 'Tab') {
      const next = current
        ? nextObjectInOrder(
            element,
            current,
            event.shiftKey ? -1 : 1,
            options,
            cache,
          )
        : (objects(element, options, cache)[0] ?? null);
      if (!next) return;
      consume(event);
      selectObject(next, event, { reveal: true });
      return;
    }

    if (isArrowKey(event.key)) {
      const object = current ?? objects(element, options, cache)[0];
      if (!object) return;
      consume(event);
      if (objectKindFor(object, options) === 'edge') return;
      if (canvasModeFor(element) === 'change') {
        const step = event.shiftKey ? 10 : 1;
        options.onNudge?.(
          selectionForObject(element, object, options, cache),
          arrowDelta(event.key, step),
          event,
        );
        selectObject(object, event, { reveal: true });
        return;
      }
      const next = nearestObjectForArrow(
        element,
        object,
        event.key,
        options,
        cache,
      );
      if (next) selectObject(next, event, { reveal: true });
    }
  };

  const mutationObserver = new MutationObserver(invalidateAndSchedule);
  mutationObserver.observe(element, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: [
      'class',
      'data-id',
      'data-ladder-id',
      'data-selected',
      'data-surface-canvas-edge',
      'data-surface-component',
      'data-canvas-object',
    ],
  });

  element.addEventListener('click', onClick);
  element.addEventListener('dblclick', onDblClick);
  element.addEventListener('pointerdown', onPointerDown);
  element.addEventListener('keydown', onKeydown);
  view.addEventListener('keydown', onKeydown, true);
  view.addEventListener('scroll', invalidateAndSchedule, true);
  view.addEventListener('resize', invalidateAndSchedule);
  syncRuntime();
  schedule();

  return () => {
    if (frame !== 0) view.cancelAnimationFrame(frame);
    unsubscribe?.();
    mutationObserver.disconnect();
    endActivePointer('cancel');
    endActiveMarquee('cancel');
    endActiveConnection('cancel');
    element.removeEventListener('click', onClick);
    element.removeEventListener('dblclick', onDblClick);
    element.removeEventListener('pointerdown', onPointerDown);
    element.removeEventListener('keydown', onKeydown);
    view.removeEventListener('keydown', onKeydown, true);
    view.removeEventListener('scroll', invalidateAndSchedule, true);
    view.removeEventListener('resize', invalidateAndSchedule);
  };

  function beginPointerMove(object: HTMLElement, event: PointerEvent): void {
    const selection = selectionForObject(element, object, options, cache);
    selectObject(object, event, {
      reveal: false,
      additive: event.metaKey || event.ctrlKey,
      range: event.shiftKey,
    });
    activePointer = {
      kind: 'move',
      object,
      selection,
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      initialTransform: object.style.transform,
      initialWidth: object.offsetWidth,
      initialHeight: object.offsetHeight,
    };
    beginPointerSession(object, event);
    options.onMove?.(
      selection,
      pointerMoveFor(event, activePointer, 'start'),
      event,
    );
  }

  function beginPointerResize(object: HTMLElement, event: PointerEvent): void {
    const selection = selectionForObject(element, object, options, cache);
    selectObject(object, event, {
      reveal: false,
      additive: event.metaKey || event.ctrlKey,
      range: event.shiftKey,
    });
    activePointer = {
      kind: 'resize',
      object,
      selection,
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      initialTransform: object.style.transform,
      initialWidth: object.offsetWidth,
      initialHeight: object.offsetHeight,
    };
    beginPointerSession(object, event);
    options.onResize?.(
      selection,
      pointerResizeFor(event, activePointer, 'start', options),
      event,
    );
  }

  function beginPointerSession(object: HTMLElement, event: PointerEvent): void {
    consumePointer(event);
    object.dataset['surfaceCanvasPointerActive'] = 'true';
    element.dataset['surfaceCanvasPointerActive'] =
      activePointer?.kind ?? 'true';
    previousBodyUserSelect = element.ownerDocument.body.style.userSelect;
    element.ownerDocument.body.style.userSelect = 'none';
    view.addEventListener('pointermove', onWindowPointerMove, true);
    view.addEventListener('pointerup', onWindowPointerUp, true);
    view.addEventListener('pointercancel', onWindowPointerCancel, true);
  }

  function onWindowPointerMove(event: PointerEvent): void {
    if (activeConnection && event.pointerId === activeConnection.pointerId) {
      consumePointer(event);
      updateActiveConnection(event, 'move');
      return;
    }
    if (activeMarquee && event.pointerId === activeMarquee.pointerId) {
      consumePointer(event);
      updateActiveMarquee(event, 'move');
      return;
    }
    if (!activePointer || event.pointerId !== activePointer.pointerId) return;
    consumePointer(event);
    if (activePointer.kind === 'move') {
      const move = snappedPointerMoveFor(event, activePointer, 'move', options);
      applyMoveTransform(
        activePointer.object,
        activePointer.initialTransform,
        move.totalDx,
        move.totalDy,
      );
      invalidateGeometry(activePointer.object);
      emitAutoPan(event, 'move');
      options.onMove?.(activePointer.selection, move, event);
      return;
    }
    const resize = pointerResizeFor(event, activePointer, 'move', options);
    activePointer.object.style.width = `${resize.width}px`;
    activePointer.object.style.height = `${resize.height}px`;
    invalidateGeometry(activePointer.object);
    emitAutoPan(event, 'move');
    options.onResize?.(activePointer.selection, resize, event);
  }

  function onWindowPointerUp(event: PointerEvent): void {
    if (activeConnection && event.pointerId === activeConnection.pointerId) {
      consumePointer(event);
      endActiveConnection('end', event);
      return;
    }
    if (activeMarquee && event.pointerId === activeMarquee.pointerId) {
      consumePointer(event);
      endActiveMarquee('end', event);
      return;
    }
    if (!activePointer || event.pointerId !== activePointer.pointerId) return;
    consumePointer(event);
    endActivePointer('end', event);
  }

  function onWindowPointerCancel(event: PointerEvent): void {
    if (activeConnection && event.pointerId === activeConnection.pointerId) {
      consumePointer(event);
      endActiveConnection('cancel', event);
      return;
    }
    if (activeMarquee && event.pointerId === activeMarquee.pointerId) {
      consumePointer(event);
      endActiveMarquee('cancel', event);
      return;
    }
    if (!activePointer || event.pointerId !== activePointer.pointerId) return;
    consumePointer(event);
    endActivePointer('cancel', event);
  }

  function endActivePointer(
    phase: 'end' | 'cancel',
    event?: PointerEvent,
  ): void {
    if (!activePointer) return;
    const session = activePointer;
    activePointer = null;
    view.removeEventListener('pointermove', onWindowPointerMove, true);
    view.removeEventListener('pointerup', onWindowPointerUp, true);
    view.removeEventListener('pointercancel', onWindowPointerCancel, true);
    element.ownerDocument.body.style.userSelect = previousBodyUserSelect;
    delete element.dataset['surfaceCanvasPointerActive'];
    delete session.object.dataset['surfaceCanvasPointerActive'];

    if (session.kind === 'move') {
      const move = event
        ? phase === 'end'
          ? snappedPointerMoveFor(event, session, phase, options)
          : pointerMoveFor(event, session, phase)
        : pointerMoveForFallback(session, phase);
      if (phase === 'cancel') {
        session.object.style.transform = session.initialTransform;
        dispatchSurfaceGeometryChange(session.object);
      }
      options.onMove?.(session.selection, move, event);
      if (phase === 'end') {
        view.requestAnimationFrame(() => {
          session.object.style.transform = session.initialTransform;
          dispatchSurfaceGeometryChange(session.object);
        });
      }
    } else {
      const resize = event
        ? pointerResizeFor(event, session, phase, options)
        : pointerResizeForFallback(session, phase, options);
      if (phase === 'cancel') {
        session.object.style.width = `${session.initialWidth}px`;
        session.object.style.height = `${session.initialHeight}px`;
        dispatchSurfaceGeometryChange(session.object);
      }
      options.onResize?.(session.selection, resize, event);
    }
    if (event) emitAutoPan(event, phase);
    invalidateGeometry(session.object);
  }

  function emitAutoPan(
    event: PointerEvent,
    phase: SurfaceCanvasPointerPhase,
  ): void {
    if (!canvasAutoPanEnabled(options)) return;
    const autoPan = autoPanForPointer(element, event, phase, options);
    if (!autoPan) return;
    if (phase === 'move' && autoPan.dx === 0 && autoPan.dy === 0) return;
    options.onAutoPan?.(autoPan, event);
  }

  function beginConnection(handle: HTMLElement, event: PointerEvent): void {
    const handleInfo = connectionHandleInfo(handle);
    if (!handleInfo.nodeId) return;
    consumePointer(event);
    activeConnection = {
      pointerId: event.pointerId,
      sourceId: handleInfo.nodeId,
      sourceHandleId: handleInfo.handleId,
      sourceHandleType: handleInfo.handleType,
      targetId: null,
      targetHandleId: null,
      targetHandleType: null,
    };
    element.dataset['surfaceCanvasPointerActive'] = 'connect';
    handle.dataset['surfaceCanvasConnectionSource'] = 'true';
    previousBodyUserSelect = element.ownerDocument.body.style.userSelect;
    element.ownerDocument.body.style.userSelect = 'none';
    syncRuntime()?.dispatch({
      type: 'connectStart',
      sourceId: handleInfo.nodeId,
      sourceHandleId: handleInfo.handleId,
    });
    view.addEventListener('pointermove', onWindowPointerMove, true);
    view.addEventListener('pointerup', onWindowPointerUp, true);
    view.addEventListener('pointercancel', onWindowPointerCancel, true);
    options.onConnectStart?.(
      connectionForSession(activeConnection, event, 'start'),
      event,
    );
  }

  function updateActiveConnection(
    event: PointerEvent,
    phase: SurfaceCanvasPointerPhase,
  ): SurfaceCanvasConnection | null {
    if (!activeConnection) return null;
    const targetHandle = connectHandleAtPoint(element, event, options);
    const targetInfo = targetHandle ? connectionHandleInfo(targetHandle) : null;
    activeConnection.targetId = targetInfo?.nodeId ?? null;
    activeConnection.targetHandleId = targetInfo?.handleId ?? null;
    activeConnection.targetHandleType = targetInfo?.handleType ?? null;
    if (targetInfo?.nodeId) {
      syncRuntime()?.dispatch({
        type: 'connectOver',
        targetId: targetInfo.nodeId,
        targetHandleId: targetInfo.handleId,
      });
    }
    const connection = connectionForSession(activeConnection, event, phase);
    options.onConnectUpdate?.(connection, event);
    emitAutoPan(event, phase);
    return connection;
  }

  function endActiveConnection(
    phase: 'end' | 'cancel',
    event?: PointerEvent,
  ): void {
    if (!activeConnection) return;
    const session = activeConnection;
    const connection = event
      ? updateActiveConnection(event, phase)
      : connectionForSessionFromFallback(session, phase);
    activeConnection = null;
    view.removeEventListener('pointermove', onWindowPointerMove, true);
    view.removeEventListener('pointerup', onWindowPointerUp, true);
    view.removeEventListener('pointercancel', onWindowPointerCancel, true);
    element.ownerDocument.body.style.userSelect = previousBodyUserSelect;
    delete element.dataset['surfaceCanvasPointerActive'];
    for (const source of element.querySelectorAll<HTMLElement>(
      '[data-surface-canvas-connection-source="true"]',
    )) {
      delete source.dataset['surfaceCanvasConnectionSource'];
    }
    syncRuntime()?.dispatch({ type: 'connectEnd' });
    if (connection && phase === 'end' && connection.targetId) {
      options.onConnect?.(connection, event);
    }
    if (connection) {
      options.onConnectEnd?.(connection, event);
    }
  }

  function beginMarquee(event: PointerEvent): void {
    ensureMarqueeStyles(element.ownerDocument);
    consumePointer(event);
    const overlay = element.ownerDocument.createElement('div');
    overlay.className = 'bx-surface-canvas-marquee';
    overlay.dataset['surfaceCanvasMarquee'] = 'active';
    element.ownerDocument.body.append(overlay);
    activeMarquee = {
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      currentX: event.clientX,
      currentY: event.clientY,
      additive: event.metaKey || event.ctrlKey || event.shiftKey,
      overlay,
    };
    element.dataset['surfaceCanvasPointerActive'] = 'marquee';
    previousBodyUserSelect = element.ownerDocument.body.style.userSelect;
    element.ownerDocument.body.style.userSelect = 'none';
    view.addEventListener('pointermove', onWindowPointerMove, true);
    view.addEventListener('pointerup', onWindowPointerUp, true);
    view.addEventListener('pointercancel', onWindowPointerCancel, true);
    applyMarqueeOverlay(activeMarquee);
    options.onMarqueeStart?.(
      marqueeForSession(element, activeMarquee, 'start', options, cache),
      event,
    );
  }

  function updateActiveMarquee(
    event: PointerEvent,
    phase: SurfaceCanvasPointerPhase,
  ): void {
    if (!activeMarquee) return;
    activeMarquee.currentX = event.clientX;
    activeMarquee.currentY = event.clientY;
    applyMarqueeOverlay(activeMarquee);
    options.onMarqueeUpdate?.(
      marqueeForSession(element, activeMarquee, phase, options, cache),
      event,
    );
  }

  function endActiveMarquee(
    phase: 'end' | 'cancel',
    event?: PointerEvent,
  ): void {
    if (!activeMarquee) return;
    const session = activeMarquee;
    if (event) {
      session.currentX = event.clientX;
      session.currentY = event.clientY;
    }
    activeMarquee = null;
    view.removeEventListener('pointermove', onWindowPointerMove, true);
    view.removeEventListener('pointerup', onWindowPointerUp, true);
    view.removeEventListener('pointercancel', onWindowPointerCancel, true);
    element.ownerDocument.body.style.userSelect = previousBodyUserSelect;
    delete element.dataset['surfaceCanvasPointerActive'];
    session.overlay.remove();
    suppressNextClick = true;

    const marquee = marqueeForSession(element, session, phase, options, cache);
    if (phase === 'end') {
      commitMarqueeSelection(marquee, event);
      options.onMarqueeCommit?.(marquee, event);
    } else {
      options.onMarqueeUpdate?.(marquee, event);
    }
  }

  function commitMarqueeSelection(
    marquee: SurfaceCanvasMarquee,
    event?: PointerEvent,
  ): void {
    const currentRuntime = syncRuntime();
    if (!currentRuntime) return;
    if (marquee.ids.length === 0) {
      if (!marquee.additive) clearSelection(event);
      return;
    }
    delete element.dataset['surfaceCanvasSelectionCleared'];
    hasHydratedSelection = true;
    if (!marquee.additive) {
      currentRuntime.clearInteractionState();
    }
    for (const [index, id] of marquee.ids.entries()) {
      currentRuntime.select(id, {
        additive: marquee.additive || index > 0,
        restoreSource: true,
      });
    }
    schedule();
  }
});

function consume(event: KeyboardEvent): void {
  event.preventDefault();
  event.stopPropagation();
  event.stopImmediatePropagation();
}

function canvasModeFor(element: HTMLElement): 'use' | 'change' | 'inspect' {
  const mode = element
    .closest<HTMLElement>('[data-surface-mode]')
    ?.getAttribute('data-surface-mode');
  return mode === 'change' || mode === 'inspect' ? mode : 'use';
}

function activeSelectionId(runtime: SurfaceRuntime): string | null {
  const snapshot = runtime.snapshot();
  const activeScopeId = snapshot.activeScopeId;
  if (activeScopeId && snapshot.selections[activeScopeId]) {
    return snapshot.selections[activeScopeId]!.headId;
  }
  return snapshot.focusedId;
}

function activeObjectElement(
  root: HTMLElement,
  runtime: SurfaceRuntime,
  options: SurfaceCanvasBindingOptions,
  cache?: SurfaceDomBindingCache,
): HTMLElement | null {
  const activeId = activeSelectionId(runtime);
  return activeId ? objectById(root, activeId, options, cache) : null;
}

function objectById(
  root: HTMLElement,
  id: string,
  options: SurfaceCanvasBindingOptions,
  cache?: SurfaceDomBindingCache,
): HTMLElement | null {
  return (
    objects(root, options, cache).find(
      (object) => surfaceIdFor(object) === id,
    ) ?? null
  );
}

function closestObject(
  root: HTMLElement,
  target: Element | null,
  options: SurfaceCanvasBindingOptions,
): HTMLElement | null {
  if (!target) return null;
  const selector = canvasObjectSelector(options);
  const object = target.closest<HTMLElement>(selector);
  if (!object || !root.contains(object)) return null;
  if (object.closest('[data-bx-lift]')) return null;
  return object;
}

function objects(
  root: HTMLElement,
  options: SurfaceCanvasBindingOptions,
  cache?: SurfaceDomBindingCache,
): HTMLElement[] {
  const selector = canvasObjectSelector(options);
  return cachedElementList(cache, root, `canvas:objects:${selector}`, () =>
    Array.from(root.querySelectorAll<HTMLElement>(selector)).filter(
      (object) => root.contains(object) && isVisible(object),
    ),
  );
}

function rectForObject(
  object: HTMLElement,
  cache?: SurfaceDomBindingCache,
): DOMRect {
  return cachedRectForElement(object, cache);
}

function surfaceIdFor(element: HTMLElement): string | null {
  return (
    element.getAttribute('data-ladder-id') ??
    element.getAttribute('data-id') ??
    element.id ??
    null
  );
}

function paintObjectSelectionState(
  object: HTMLElement,
  selected: boolean,
  projected: FociProjectionNode | undefined,
): void {
  const selectedValue = selected ? 'true' : 'false';
  if (object.dataset['runtimeSelected'] !== selectedValue) {
    object.dataset['runtimeSelected'] = selectedValue;
  }
  if (object.dataset['selected'] !== selectedValue) {
    object.dataset['selected'] = selectedValue;
  }
  object.classList.toggle('is-runtime-selected', selected);
  const tabIndex = tabIndexForObjectProjection(selected, projected);
  if (tabIndex === null) {
    object.removeAttribute('tabindex');
  } else {
    object.tabIndex = tabIndex;
  }
}

function tabIndexForObjectProjection(
  selected: boolean,
  projected: FociProjectionNode | undefined,
): 0 | -1 | null {
  return projected?.tabIndex ?? (selected ? 0 : -1);
}

function symmetricDifference(
  left: ReadonlySet<string>,
  right: ReadonlySet<string>,
): Set<string> {
  const changed = new Set<string>();
  for (const id of left) {
    if (!right.has(id)) changed.add(id);
  }
  for (const id of right) {
    if (!left.has(id)) changed.add(id);
  }
  return changed;
}

function selectionForObject(
  root: HTMLElement,
  object: HTMLElement,
  options: SurfaceCanvasBindingOptions,
  cache?: SurfaceDomBindingCache,
  event?: Event,
): SurfaceCanvasSelection {
  const allObjects = objects(root, options, cache);
  const rect = rectForObject(object, cache);
  const targetPayload = canvasTargetPayload(event?.target);
  return {
    id: surfaceIdFor(object) ?? object.id,
    focusKey: object.dataset['surfaceFocusKey'],
    kind: objectKindFor(object, options),
    field: targetPayload.field,
    payload: targetPayload.payload,
    index: allObjects.indexOf(object),
    x: rect.left,
    y: rect.top,
    width: rect.width,
    height: rect.height,
  };
}

function canvasTargetPayload(target: EventTarget | null | undefined): {
  field?: string;
  payload?: Record<string, string>;
} {
  if (!(target instanceof Element)) return {};
  const payloadElement = closestCanvasPayloadElement(target);
  if (!payloadElement) return {};
  const payload: Record<string, string> = {};
  for (const { name, value } of Array.from(payloadElement.attributes)) {
    if (!name.startsWith('data-canvas-')) continue;
    const key = datasetPayloadKey(name.slice('data-canvas-'.length));
    if (key) payload[key] = value;
  }
  return {
    field: payload['field'],
    payload: Object.keys(payload).length > 0 ? payload : undefined,
  };
}

function closestCanvasPayloadElement(target: Element): HTMLElement | null {
  let cursor: Element | null = target;
  while (cursor) {
    if (
      cursor instanceof HTMLElement &&
      Array.from(cursor.attributes).some((attribute) =>
        attribute.name.startsWith('data-canvas-'),
      )
    ) {
      return cursor;
    }
    cursor = cursor.parentElement;
  }
  return null;
}

function datasetPayloadKey(attributeSuffix: string): string {
  return attributeSuffix.replace(/-([a-z])/g, (_match, char: string) =>
    char.toUpperCase(),
  );
}

function canvasObjectSelector(options: SurfaceCanvasBindingOptions): string {
  const objectSelector = options.objectSelector ?? DEFAULT_OBJECT_SELECTOR;
  const edgeSelector = options.edgeSelector ?? DEFAULT_EDGE_SELECTOR;
  return [objectSelector, edgeSelector]
    .filter((selector) => selector.trim().length > 0)
    .join(', ');
}

function objectKindFor(
  object: HTMLElement,
  options: SurfaceCanvasBindingOptions,
): SurfaceCanvasObjectKind {
  const edgeSelector = options.edgeSelector ?? DEFAULT_EDGE_SELECTOR;
  if (edgeSelector.trim().length > 0 && object.matches(edgeSelector)) {
    return 'edge';
  }
  return object.getAttribute('data-surface-component') === 'edge' ||
    object.hasAttribute('data-surface-canvas-edge') ||
    object.classList.contains('boxel-canvas__edge')
    ? 'edge'
    : 'frame';
}

function nextObjectInOrder(
  root: HTMLElement,
  current: HTMLElement,
  direction: 1 | -1,
  options: SurfaceCanvasBindingOptions,
  cache?: SurfaceDomBindingCache,
): HTMLElement | null {
  const allObjects = objects(root, options, cache);
  if (allObjects.length === 0) return null;
  const currentIndex = allObjects.indexOf(current);
  const nextIndex =
    currentIndex < 0
      ? 0
      : (currentIndex + direction + allObjects.length) % allObjects.length;
  return allObjects[nextIndex] ?? null;
}

function nearestObjectForArrow(
  root: HTMLElement,
  current: HTMLElement,
  key: string,
  options: SurfaceCanvasBindingOptions,
  cache?: SurfaceDomBindingCache,
): HTMLElement | null {
  const currentRect = rectForObject(current, cache);
  const currentCenter = centerOf(currentRect);
  let best: { object: HTMLElement; score: number } | null = null;

  for (const candidate of objects(root, options, cache)) {
    if (candidate === current) continue;
    const rect = rectForObject(candidate, cache);
    const center = centerOf(rect);
    const dx = center.x - currentCenter.x;
    const dy = center.y - currentCenter.y;
    if (!isCandidateInDirection(key, dx, dy)) continue;
    const primary =
      key === 'ArrowLeft' || key === 'ArrowRight' ? Math.abs(dx) : Math.abs(dy);
    const secondary =
      key === 'ArrowLeft' || key === 'ArrowRight' ? Math.abs(dy) : Math.abs(dx);
    const overlapBias = overlapsOrthogonalAxis(key, currentRect, rect)
      ? -1000
      : 0;
    const score = primary * 100 + secondary + overlapBias;
    if (!best || score < best.score) best = { object: candidate, score };
  }

  return best?.object ?? current;
}

function centerOf(rect: DOMRect): { x: number; y: number } {
  return {
    x: rect.left + rect.width / 2,
    y: rect.top + rect.height / 2,
  };
}

function isCandidateInDirection(key: string, dx: number, dy: number): boolean {
  switch (key) {
    case 'ArrowLeft':
      return dx < 0 && Math.abs(dx) >= Math.abs(dy) * 0.2;
    case 'ArrowRight':
      return dx > 0 && Math.abs(dx) >= Math.abs(dy) * 0.2;
    case 'ArrowUp':
      return dy < 0 && Math.abs(dy) >= Math.abs(dx) * 0.2;
    case 'ArrowDown':
      return dy > 0 && Math.abs(dy) >= Math.abs(dx) * 0.2;
    default:
      return false;
  }
}

function overlapsOrthogonalAxis(key: string, a: DOMRect, b: DOMRect): boolean {
  if (key === 'ArrowLeft' || key === 'ArrowRight') {
    return a.top <= b.bottom && b.top <= a.bottom;
  }
  return a.left <= b.right && b.left <= a.right;
}

function isArrowKey(key: string): boolean {
  return (
    key === 'ArrowUp' ||
    key === 'ArrowDown' ||
    key === 'ArrowLeft' ||
    key === 'ArrowRight'
  );
}

function arrowDelta(key: string, step: number): { dx: number; dy: number } {
  switch (key) {
    case 'ArrowLeft':
      return { dx: -step, dy: 0 };
    case 'ArrowRight':
      return { dx: step, dy: 0 };
    case 'ArrowUp':
      return { dx: 0, dy: -step };
    case 'ArrowDown':
      return { dx: 0, dy: step };
    default:
      return { dx: 0, dy: 0 };
  }
}

function canvasPointerDragEnabled(
  options: SurfaceCanvasBindingOptions,
): boolean {
  return options.pointerDrag ?? Boolean(options.onMove);
}

function canvasPointerResizeEnabled(
  options: SurfaceCanvasBindingOptions,
): boolean {
  return options.pointerResize ?? Boolean(options.onResize);
}

function canvasPointerMarqueeEnabled(
  options: SurfaceCanvasBindingOptions,
): boolean {
  return (
    options.pointerMarquee ??
    Boolean(
      options.onMarqueeStart ||
      options.onMarqueeUpdate ||
      options.onMarqueeCommit,
    )
  );
}

function canvasPointerConnectEnabled(
  options: SurfaceCanvasBindingOptions,
): boolean {
  return (
    options.pointerConnect ??
    Boolean(
      options.onConnectStart ||
      options.onConnectUpdate ||
      options.onConnect ||
      options.onConnectEnd,
    )
  );
}

function canvasAutoPanEnabled(options: SurfaceCanvasBindingOptions): boolean {
  return options.autoPan ?? Boolean(options.onAutoPan);
}

function autoPanForPointer(
  root: HTMLElement,
  event: PointerEvent,
  phase: SurfaceCanvasPointerPhase,
  options: SurfaceCanvasBindingOptions,
): SurfaceCanvasAutoPan | null {
  const rect = root.getBoundingClientRect();
  if (rect.width <= 0 || rect.height <= 0) return null;
  const margin = options.autoPanMargin ?? 48;
  const maxSpeed = options.autoPanMaxSpeed ?? 18;
  const dx = autoPanAxisDelta(
    event.clientX,
    rect.left,
    rect.right,
    margin,
    maxSpeed,
  );
  const dy = autoPanAxisDelta(
    event.clientY,
    rect.top,
    rect.bottom,
    margin,
    maxSpeed,
  );
  return {
    dx,
    dy,
    pointerX: event.clientX,
    pointerY: event.clientY,
    margin,
    phase,
  };
}

function autoPanAxisDelta(
  pointer: number,
  start: number,
  end: number,
  margin: number,
  maxSpeed: number,
): number {
  if (margin <= 0 || maxSpeed <= 0) return 0;
  if (pointer < start + margin) {
    const pressure = (start + margin - pointer) / margin;
    return -Math.round(Math.min(1, Math.max(0, pressure)) * maxSpeed);
  }
  if (pointer > end - margin) {
    const pressure = (pointer - (end - margin)) / margin;
    return Math.round(Math.min(1, Math.max(0, pressure)) * maxSpeed);
  }
  return 0;
}

function ensureMarqueeStyles(document: Document): void {
  if (document.getElementById(MARQUEE_STYLE_ID)) return;
  const style = document.createElement('style');
  style.id = MARQUEE_STYLE_ID;
  style.textContent = `
    .bx-surface-canvas-marquee {
      position: fixed;
      z-index: 98;
      box-sizing: border-box;
      pointer-events: none;
      border: 1px solid var(--surface-decal-highlight, #00ffba);
      background: var(--surface-decal-highlight-fill-soft, rgba(0, 255, 186, 0.10));
      box-shadow: 0 0 0 3px var(--surface-decal-highlight-fill-soft, rgba(0, 255, 186, 0.10));
    }
  `;
  document.head.append(style);
}

function applyMarqueeOverlay(session: ActiveCanvasMarquee): void {
  const box = marqueeBoxForSession(session);
  session.overlay.style.left = `${box.left}px`;
  session.overlay.style.top = `${box.top}px`;
  session.overlay.style.width = `${box.width}px`;
  session.overlay.style.height = `${box.height}px`;
}

function marqueeForSession(
  root: HTMLElement,
  session: ActiveCanvasMarquee,
  phase: SurfaceCanvasPointerPhase,
  options: SurfaceCanvasBindingOptions,
  cache?: SurfaceDomBindingCache,
): SurfaceCanvasMarquee {
  const box = marqueeBoxForSession(session);
  return {
    phase,
    startX: session.startX,
    startY: session.startY,
    currentX: session.currentX,
    currentY: session.currentY,
    left: box.left,
    top: box.top,
    right: box.right,
    bottom: box.bottom,
    width: box.width,
    height: box.height,
    pointerX: session.currentX,
    pointerY: session.currentY,
    ids: marqueeObjectIds(root, box, options, cache),
    additive: session.additive,
  };
}

function marqueeBoxForSession(session: ActiveCanvasMarquee): {
  left: number;
  top: number;
  right: number;
  bottom: number;
  width: number;
  height: number;
} {
  const left = Math.min(session.startX, session.currentX);
  const top = Math.min(session.startY, session.currentY);
  const right = Math.max(session.startX, session.currentX);
  const bottom = Math.max(session.startY, session.currentY);
  return {
    left,
    top,
    right,
    bottom,
    width: right - left,
    height: bottom - top,
  };
}

function marqueeObjectIds(
  root: HTMLElement,
  box: {
    left: number;
    top: number;
    right: number;
    bottom: number;
    width: number;
    height: number;
  },
  options: SurfaceCanvasBindingOptions,
  cache?: SurfaceDomBindingCache,
): string[] {
  const minSize = options.marqueeMinSize ?? 4;
  if (box.width < minSize && box.height < minSize) return [];
  const ids: string[] = [];
  for (const object of objects(root, options, cache)) {
    if (!rectsIntersect(rectForObject(object, cache), box)) continue;
    const id = surfaceIdFor(object);
    if (id) ids.push(id);
  }
  return ids;
}

function rectsIntersect(
  rect: DOMRect,
  box: { left: number; top: number; right: number; bottom: number },
): boolean {
  return (
    rect.left <= box.right &&
    rect.right >= box.left &&
    rect.top <= box.bottom &&
    rect.bottom >= box.top
  );
}

function closestResizeHandle(
  root: HTMLElement,
  target: Element,
  options: SurfaceCanvasBindingOptions,
): HTMLElement | null {
  const selector =
    options.resizeHandleSelector ?? DEFAULT_RESIZE_HANDLE_SELECTOR;
  const handle = target.closest<HTMLElement>(selector);
  return handle && root.contains(handle) ? handle : null;
}

function closestConnectHandle(
  root: HTMLElement,
  target: Element,
  options: SurfaceCanvasBindingOptions,
): HTMLElement | null {
  const selector =
    options.connectHandleSelector ?? DEFAULT_CONNECT_HANDLE_SELECTOR;
  if (selector.trim().length === 0) return null;
  const handle = target.closest<HTMLElement>(selector);
  return handle && root.contains(handle) ? handle : null;
}

function connectHandleAtPoint(
  root: HTMLElement,
  event: PointerEvent,
  options: SurfaceCanvasBindingOptions,
): HTMLElement | null {
  const document = root.ownerDocument;
  const elements = document.elementsFromPoint(event.clientX, event.clientY);
  for (const element of elements) {
    const handle = closestConnectHandle(root, element, options);
    if (handle) return handle;
  }
  return null;
}

function connectionHandleInfo(handle: HTMLElement): {
  nodeId: string | null;
  handleId: string | null;
  handleType: string | null;
} {
  return {
    nodeId:
      handle.getAttribute('data-nodeid') ??
      handle.getAttribute('data-surface-node-id') ??
      handle.getAttribute('data-ladder-id') ??
      null,
    handleId:
      handle.getAttribute('data-handleid') ??
      handle.getAttribute('data-surface-handle-id') ??
      null,
    handleType:
      handle.getAttribute('data-handletype') ??
      handle.getAttribute('data-surface-handle-type') ??
      null,
  };
}

function connectionForSession(
  session: ActiveCanvasConnection,
  event: PointerEvent,
  phase: SurfaceCanvasPointerPhase,
): SurfaceCanvasConnection {
  return {
    phase,
    sourceId: session.sourceId,
    sourceHandleId: session.sourceHandleId,
    sourceHandleType: session.sourceHandleType,
    targetId: session.targetId,
    targetHandleId: session.targetHandleId,
    targetHandleType: session.targetHandleType,
    pointerX: event.clientX,
    pointerY: event.clientY,
  };
}

function connectionForSessionFromFallback(
  session: ActiveCanvasConnection,
  phase: SurfaceCanvasPointerPhase,
): SurfaceCanvasConnection {
  return {
    phase,
    sourceId: session.sourceId,
    sourceHandleId: session.sourceHandleId,
    sourceHandleType: session.sourceHandleType,
    targetId: session.targetId,
    targetHandleId: session.targetHandleId,
    targetHandleType: session.targetHandleType,
    pointerX: 0,
    pointerY: 0,
  };
}

function isCanvasDragStartTarget(
  object: HTMLElement,
  target: Element,
  options: SurfaceCanvasBindingOptions,
): boolean {
  const selector = options.dragHandleSelector ?? DEFAULT_DRAG_HANDLE_SELECTOR;
  const handle = target.closest<HTMLElement>(selector);
  if (handle && object.contains(handle)) return true;
  if (object.querySelector(selector)) return false;
  return (
    target.closest(
      'button, input, textarea, select, [contenteditable]:not([contenteditable=false]), [data-surface-activate-frame], [data-surface-atom-editor]',
    ) === null
  );
}

function consumePointer(event: PointerEvent): void {
  event.preventDefault();
  event.stopPropagation();
  event.stopImmediatePropagation();
}

function pointerMoveFor(
  event: PointerEvent,
  session: ActiveCanvasPointer,
  phase: SurfaceCanvasPointerPhase,
): SurfaceCanvasMove {
  const totalDx = event.clientX - session.startX;
  const totalDy = event.clientY - session.startY;
  return {
    phase,
    dx: totalDx,
    dy: totalDy,
    totalDx,
    totalDy,
    pointerX: event.clientX,
    pointerY: event.clientY,
  };
}

function snappedPointerMoveFor(
  event: PointerEvent,
  session: ActiveCanvasPointer,
  phase: SurfaceCanvasPointerPhase,
  options: SurfaceCanvasBindingOptions,
): SurfaceCanvasMove {
  return applySnapPosition(
    session.selection,
    pointerMoveFor(event, session, phase),
    options,
    event,
  );
}

function applySnapPosition(
  selection: SurfaceCanvasSelection,
  move: SurfaceCanvasMove,
  options: SurfaceCanvasBindingOptions,
  event?: PointerEvent | KeyboardEvent,
): SurfaceCanvasMove {
  const snapped = options.snapPosition?.(selection, move, event);
  if (!snapped) return move;
  const totalDx = finiteOr(
    snapped.dx,
    snapped.x === undefined ? move.totalDx : snapped.x - selection.x,
  );
  const totalDy = finiteOr(
    snapped.dy,
    snapped.y === undefined ? move.totalDy : snapped.y - selection.y,
  );
  return {
    ...move,
    dx: totalDx,
    dy: totalDy,
    totalDx,
    totalDy,
  };
}

function finiteOr(value: number | undefined, fallback: number): number {
  return value !== undefined && Number.isFinite(value) ? value : fallback;
}

function pointerMoveForFallback(
  session: ActiveCanvasPointer,
  phase: SurfaceCanvasPointerPhase,
): SurfaceCanvasMove {
  return {
    phase,
    dx: 0,
    dy: 0,
    totalDx: 0,
    totalDy: 0,
    pointerX: session.startX,
    pointerY: session.startY,
  };
}

function pointerResizeFor(
  event: PointerEvent,
  session: ActiveCanvasPointer,
  phase: SurfaceCanvasPointerPhase,
  options: SurfaceCanvasBindingOptions,
): SurfaceCanvasResize {
  const dx = event.clientX - session.startX;
  const dy = event.clientY - session.startY;
  return resizeForDelta(
    session,
    dx,
    dy,
    phase,
    event.clientX,
    event.clientY,
    options,
  );
}

function pointerResizeForFallback(
  session: ActiveCanvasPointer,
  phase: SurfaceCanvasPointerPhase,
  options: SurfaceCanvasBindingOptions,
): SurfaceCanvasResize {
  return resizeForDelta(
    session,
    0,
    0,
    phase,
    session.startX,
    session.startY,
    options,
  );
}

function resizeForDelta(
  session: ActiveCanvasPointer,
  dx: number,
  dy: number,
  phase: SurfaceCanvasPointerPhase,
  pointerX: number,
  pointerY: number,
  options: SurfaceCanvasBindingOptions,
): SurfaceCanvasResize {
  const minWidth = options.minResizeWidth ?? 180;
  const minHeight = options.minResizeHeight ?? 120;
  return {
    phase,
    dx,
    dy,
    width: Math.max(minWidth, session.initialWidth + dx),
    height: Math.max(minHeight, session.initialHeight + dy),
    pointerX,
    pointerY,
  };
}

function applyMoveTransform(
  object: HTMLElement,
  initialTransform: string,
  dx: number,
  dy: number,
): void {
  const base =
    initialTransform && initialTransform !== 'none'
      ? `${initialTransform} `
      : '';
  object.style.transform = `${base}translate3d(${Math.round(dx)}px, ${Math.round(dy)}px, 0)`;
}

function focusObject(
  object: HTMLElement,
  reveal: boolean,
  selection: SurfaceCanvasSelection,
  options: SurfaceCanvasBindingOptions,
): void {
  if (!surfaceTargetRetainsFocus(object.ownerDocument.activeElement)) {
    object.focus({ preventScroll: true });
  }
  if (!reveal) return;
  const revealMode = options.reveal ?? 'scroll';
  if (typeof revealMode === 'function') {
    revealMode(object, selection);
    return;
  }
  if (revealMode === 'pan') {
    options.onReveal?.(selection, object);
    return;
  }
  if (revealMode === 'scroll') {
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

function isVisible(element: HTMLElement): boolean {
  return element.offsetParent !== null || element.getClientRects().length > 0;
}

export default surfaceCanvasBinding;
