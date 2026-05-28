import { modifier } from 'ember-modifier';

import { surfaceRuntimeForElement } from '../dom-registry.ts';
import {
  isSurfaceTextEntryTarget,
  surfaceElementOwnsKeyboardEvent,
  surfaceTargetOwnsKeyboardEvent,
  surfaceTargetOwnsPointerEvent,
} from '../keyboard.ts';
import { releaseSurfaceGridDomFocus } from '../grid-dom.ts';
import {
  cachedElementList,
  createSurfaceDomBindingCache,
  type SurfaceDomBindingCache,
} from './dom-binding-cache.ts';
import type { SurfaceRuntime } from '../surface-runtime.ts';
export {
  cancelSurfaceGridInput,
  clearSurfaceGridSelection,
  commitSurfaceGridInput,
  releaseSurfaceGridDomFocus,
  restoreSurfaceGridSelection,
} from '../grid-dom.ts';
export type {
  SurfaceGridCancelOptions,
  SurfaceGridCommitOptions,
  SurfaceGridDomOptions,
} from '../grid-dom.ts';

export interface SurfaceGridSelection {
  id: string;
  focusKey?: string;
  rowIndex: number;
  colIndex: number;
  rowKey?: string;
  colKey?: string;
}

export interface SurfaceGridBindingOptions {
  active?: boolean;
  cellSelector?: string;
  rowSelector?: string;
  onSelect?: (selection: SurfaceGridSelection, event?: Event) => void;
  onActivate?: (selection: SurfaceGridSelection, event?: Event) => void;
  onClear?: (event?: Event) => void;
}

const DEFAULT_CELL_SELECTOR =
  '[data-surface-component="cell"][role="gridcell"], [role="gridcell"]';
const DEFAULT_ROW_SELECTOR =
  '[data-surface-component="row"][role="row"], [role="row"]';

const GRID_KEYS = new Set([
  'ArrowUp',
  'ArrowDown',
  'ArrowLeft',
  'ArrowRight',
  'Home',
  'End',
  'PageUp',
  'PageDown',
  'Tab',
  'Enter',
  'F2',
  'Escape',
  ' ',
  'Spacebar',
]);

const surfaceGridBinding = modifier<{
  Element: HTMLElement;
  Args: {
    Positional: [];
    Named: SurfaceGridBindingOptions;
  };
}>((element, _positional, options) => {
  const view = element.ownerDocument.defaultView ?? window;
  let frame = 0;
  let runtime: SurfaceRuntime | undefined;
  let unsubscribe: (() => void) | undefined;
  let retryCount = 0;
  let hasHydratedSelection = false;
  let localActiveCellId: string | null = null;
  let cache = createSurfaceDomBindingCache();

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

  const syncRuntime = (): SurfaceRuntime | undefined => {
    const next = surfaceRuntimeForElement(element);
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
    element.dataset['surfaceGridBinding'] = active ? 'active' : 'inactive';
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
      mode: gridModeFor(element),
    });
    const runtimeActiveId = activeSelectionId(currentRuntime);
    let activeId =
      localActiveCellId ??
      element.dataset['surfaceGridActiveId'] ??
      runtimeActiveId;
    if (
      runtimeActiveId &&
      !localActiveCellId &&
      !element.dataset['surfaceGridActiveId']
    ) {
      delete element.dataset['surfaceGridSelectionCleared'];
      hasHydratedSelection = true;
      localActiveCellId = runtimeActiveId;
    }
    if (element.dataset['surfaceGridSelectionCleared'] === 'true') {
      hasHydratedSelection = true;
      localActiveCellId = null;
      activeId = null;
    }
    if (!activeId && !hasHydratedSelection) {
      const seededCell = cells(element, options, cache).find(
        (cell) =>
          cell.dataset['selected'] === 'true' ||
          cell.classList.contains('is-selected') ||
          cell.classList.contains('is-runtime-selected'),
      );
      const seededId = seededCell ? surfaceIdFor(seededCell) : null;
      if (seededId) {
        currentRuntime.select(seededId, { restoreSource: true });
        localActiveCellId = seededId;
        activeId = seededId;
      }
      hasHydratedSelection = true;
    }
    let activeCell = activeId
      ? cellById(element, activeId, options, cache)
      : null;
    if (!activeCell) {
      const fallbackId = runtimeActiveId;
      activeId = fallbackId;
      activeCell = activeId
        ? cellById(element, activeId, options, cache)
        : null;
    }
    const activePosition = activeCell
      ? selectionForCell(element, activeCell, options, cache)
      : null;

    for (const cell of cells(element, options, cache)) {
      const id = surfaceIdFor(cell);
      const projected = id ? projection.nodeMap.get(id) : undefined;
      const selected = Boolean(
        id && (projected?.selected || projected?.focused || id === activeId),
      );
      cell.dataset['runtimeSelected'] = selected ? 'true' : 'false';
      cell.dataset['selected'] = selected ? 'true' : 'false';
      cell.classList.toggle('is-runtime-selected', selected);
      if (projected?.tabIndex === null) {
        cell.removeAttribute('tabindex');
      } else if (projected?.tabIndex !== undefined) {
        cell.tabIndex = projected.tabIndex;
      } else {
        cell.tabIndex = selected ? 0 : -1;
      }
    }

    for (const [rowIndex, row] of rows(element, options, cache).entries()) {
      const selected = activePosition?.rowIndex === rowIndex;
      row.dataset['runtimeSelectedRow'] = selected ? 'true' : 'false';
      row.classList.toggle('is-runtime-selected-row', selected);
    }

    for (const header of columnHeaders(element, cache)) {
      const selected =
        activePosition?.colKey !== undefined &&
        header.dataset['colKey'] === activePosition.colKey;
      header.dataset['runtimeSelectedCol'] = selected ? 'true' : 'false';
      header.classList.toggle('is-runtime-selected-col', selected);
    }
  };

  const selectCell = (
    cell: HTMLElement,
    event: Event | undefined,
    opts: { range?: boolean; reveal?: boolean } = {},
  ): boolean => {
    if (options.active === false) return false;
    const currentRuntime = syncRuntime();
    const id = surfaceIdFor(cell);
    if (!currentRuntime || !id) return false;
    delete element.dataset['surfaceGridSelectionCleared'];
    hasHydratedSelection = true;
    localActiveCellId = id;
    element.dataset['surfaceGridActiveId'] = id;
    currentRuntime.select(id, { range: opts.range, restoreSource: true });
    focusCell(cell, opts.reveal ?? true);
    const selection = selectionForCell(element, cell, options, cache);
    options.onSelect?.(selection, event);
    const syncLocalSelection = (): void => {
      if (element.dataset['surfaceGridActiveId'] !== id) return;
      const selectedCell =
        cellById(element, id, options) ??
        cellAtPosition(element, selection, options) ??
        cell;
      if (!element.contains(selectedCell)) return;
      paintLocalSelection(element, id, selectedCell, options);
      focusCell(selectedCell, opts.reveal ?? true);
    };
    syncLocalSelection();
    view.requestAnimationFrame(() => {
      syncLocalSelection();
      view.requestAnimationFrame(syncLocalSelection);
      view.setTimeout(syncLocalSelection, 0);
    });
    schedule();
    return true;
  };

  const clearSelection = (event?: Event): boolean => {
    const currentRuntime = syncRuntime();
    const selected = currentRuntime
      ? (activeSelectionId(currentRuntime) ?? localActiveCellId)
      : localActiveCellId;
    if (!selected) return false;
    element.dataset['surfaceGridSelectionCleared'] = 'true';
    hasHydratedSelection = true;
    localActiveCellId = null;
    delete element.dataset['surfaceGridActiveId'];
    currentRuntime?.clearInteractionState();
    releaseSurfaceGridDomFocus(element);
    options.onClear?.(event);
    schedule();
    return true;
  };

  const activateCell = (cell: HTMLElement, event?: Event): void => {
    selectCell(cell, event, { reveal: true });
    const activeRuntime = syncRuntime();
    const id = surfaceIdFor(cell);
    if (activeRuntime && id && activeSelectionId(activeRuntime) === id) {
      activeRuntime.dispatch({ type: 'activate' });
    }
    options.onActivate?.(
      selectionForCell(element, cell, options, cache),
      event,
    );
  };

  const onClick = (event: MouseEvent): void => {
    if (options.active === false) return;
    const target = event.target;
    if (!(target instanceof Element)) return;
    if (target.closest('[data-bx-lift]')) return;
    if (surfaceTargetOwnsPointerEvent(target)) return;

    const cell = closestCell(element, target, options);
    if (!cell) return;
    if (target.closest('[data-surface-activate-cell]')) {
      activateCell(cell, event);
      return;
    }
    selectCell(cell, event, { range: event.shiftKey, reveal: false });
  };

  const onClickBoundary = (event: MouseEvent): void => {
    if (options.active === false) return;
    const target = event.target;
    if (!(target instanceof Element)) return;
    if (!element.contains(target)) return;
    if (target.closest('[data-bx-lift]')) return;
    event.stopPropagation();
  };

  const onDblClick = (event: MouseEvent): void => {
    if (options.active === false) return;
    const target = event.target;
    if (!(target instanceof Element)) return;
    if (surfaceTargetOwnsPointerEvent(target)) return;
    const cell = closestCell(element, target, options);
    if (!cell) return;
    activateCell(cell, event);
    event.stopPropagation();
  };

  const onKeydown = (event: KeyboardEvent): void => {
    if (options.active === false) return;
    if (!GRID_KEYS.has(event.key)) return;
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
      activeCellElement(
        element,
        currentRuntime,
        options,
        cache,
        localActiveCellId ?? element.dataset['surfaceGridActiveId'] ?? null,
      ) ?? closestCell(element, element.ownerDocument.activeElement, options);
    if (!current && !isGridEntryKey(event.key)) return;

    if (event.key === 'Escape') {
      if (clearSelection(event)) consume(event);
      return;
    }

    if (event.key === 'Enter' || event.key === 'F2') {
      const cell = current ?? cells(element, options, cache)[0];
      if (!cell) return;
      consume(event);
      activateCell(cell, event);
      return;
    }

    if ((event.key === ' ' || event.key === 'Spacebar') && current) {
      const atom = current.querySelector<HTMLElement>(
        'button[role="checkbox"], button[role="switch"], .ss-star, [data-surface-atom-editor]',
      );
      if (atom) {
        consume(event);
        atom.click();
        selectCell(current, event, { reveal: false });
        return;
      }
    }

    const next = current
      ? nextCellForKey(element, current, event, options, cache)
      : (cells(element, options, cache)[0] ?? null);
    if (!next) return;
    consume(event);
    selectCell(next, event, {
      range: event.shiftKey && event.key !== 'Tab',
      reveal: true,
    });
  };

  const mutationObserver = new MutationObserver(invalidateAndSchedule);
  mutationObserver.observe(element, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: [
      'data-ladder-id',
      'data-selected',
      'data-surface-component',
      'role',
      'data-surface-grid-selection-cleared',
    ],
  });

  element.addEventListener('click', onClick, true);
  element.addEventListener('click', onClickBoundary);
  element.addEventListener('dblclick', onDblClick);
  element.addEventListener('keydown', onKeydown);
  view.addEventListener('keydown', onKeydown, true);
  syncRuntime();
  schedule();

  return () => {
    if (frame !== 0) view.cancelAnimationFrame(frame);
    unsubscribe?.();
    mutationObserver.disconnect();
    element.removeEventListener('click', onClick, true);
    element.removeEventListener('click', onClickBoundary);
    element.removeEventListener('dblclick', onDblClick);
    element.removeEventListener('keydown', onKeydown);
    view.removeEventListener('keydown', onKeydown, true);
  };
});

function consume(event: KeyboardEvent): void {
  event.preventDefault();
  event.stopPropagation();
  event.stopImmediatePropagation();
}

function gridModeFor(element: HTMLElement): 'use' | 'change' | 'inspect' {
  const mode = element
    .closest<HTMLElement>('[data-surface-mode]')
    ?.getAttribute('data-surface-mode');
  return mode === 'change' || mode === 'inspect' ? mode : 'use';
}

function isGridEntryKey(key: string): boolean {
  return (
    key === 'ArrowUp' ||
    key === 'ArrowDown' ||
    key === 'ArrowLeft' ||
    key === 'ArrowRight' ||
    key === 'Home' ||
    key === 'End' ||
    key === 'PageUp' ||
    key === 'PageDown' ||
    key === 'Tab'
  );
}

function activeSelectionId(runtime: SurfaceRuntime): string | null {
  const snapshot = runtime.snapshot();
  const activeScopeId = snapshot.activeScopeId;
  if (activeScopeId && snapshot.selections[activeScopeId]) {
    return snapshot.selections[activeScopeId]!.headId;
  }
  return snapshot.focusedId;
}

function activeCellElement(
  root: HTMLElement,
  runtime: SurfaceRuntime,
  options: SurfaceGridBindingOptions,
  cache?: SurfaceDomBindingCache,
  fallbackId?: string | null,
): HTMLElement | null {
  const fallbackCell = fallbackId
    ? cellById(root, fallbackId, options, cache)
    : null;
  if (fallbackCell) return fallbackCell;
  const activeId = activeSelectionId(runtime);
  return activeId ? cellById(root, activeId, options, cache) : null;
}

function cellById(
  root: HTMLElement,
  id: string,
  options: SurfaceGridBindingOptions,
  cache?: SurfaceDomBindingCache,
): HTMLElement | null {
  return (
    cells(root, options, cache).find((cell) => surfaceIdFor(cell) === id) ??
    null
  );
}

function closestCell(
  root: HTMLElement,
  target: Element | null,
  options: SurfaceGridBindingOptions,
): HTMLElement | null {
  if (!target) return null;
  const selector = options.cellSelector ?? DEFAULT_CELL_SELECTOR;
  const cell = target.closest<HTMLElement>(selector);
  if (!cell || !root.contains(cell)) return null;
  if (cell.closest('[data-bx-lift]')) return null;
  return cell;
}

function cells(
  root: HTMLElement,
  options: SurfaceGridBindingOptions,
  cache?: SurfaceDomBindingCache,
): HTMLElement[] {
  const selector = options.cellSelector ?? DEFAULT_CELL_SELECTOR;
  return cachedElementList(cache, root, `grid:cells:${selector}`, () =>
    Array.from(root.querySelectorAll<HTMLElement>(selector)).filter(
      (cell) => root.contains(cell) && isVisible(cell),
    ),
  );
}

function rows(
  root: HTMLElement,
  options: SurfaceGridBindingOptions,
  cache?: SurfaceDomBindingCache,
): HTMLElement[] {
  const selector = options.rowSelector ?? DEFAULT_ROW_SELECTOR;
  return cachedElementList(cache, root, `grid:rows:${selector}`, () =>
    Array.from(root.querySelectorAll<HTMLElement>(selector)).filter(
      (row) => root.contains(row) && isVisible(row),
    ),
  );
}

function columnHeaders(
  root: HTMLElement,
  cache?: SurfaceDomBindingCache,
): HTMLElement[] {
  return cachedElementList(cache, root, 'grid:column-headers', () =>
    Array.from(root.querySelectorAll<HTMLElement>('[data-col-key]')),
  );
}

function rowCellsFor(
  row: HTMLElement,
  allCells: HTMLElement[],
  options: SurfaceGridBindingOptions,
  cache?: SurfaceDomBindingCache,
): HTMLElement[] {
  const selector = options.cellSelector ?? DEFAULT_CELL_SELECTOR;
  return cachedElementList(cache, row, `grid:row-cells:${selector}`, () =>
    Array.from(row.querySelectorAll<HTMLElement>(selector)).filter(
      (candidate) => allCells.includes(candidate),
    ),
  );
}

function surfaceIdFor(element: HTMLElement): string | null {
  return element.getAttribute('data-ladder-id') ?? element.id ?? null;
}

function selectionForCell(
  root: HTMLElement,
  cell: HTMLElement,
  options: SurfaceGridBindingOptions,
  cache?: SurfaceDomBindingCache,
): SurfaceGridSelection {
  const allCells = cells(root, options, cache);
  const row = cell.closest<HTMLElement>(
    options.rowSelector ?? DEFAULT_ROW_SELECTOR,
  );
  const allRows = rows(root, options, cache);
  const rowCells = row ? rowCellsFor(row, allCells, options, cache) : allCells;
  const id = surfaceIdFor(cell) ?? cell.id;

  return {
    id,
    focusKey: cell.dataset['surfaceFocusKey'],
    rowIndex: row
      ? allRows.indexOf(row)
      : Math.floor(allCells.indexOf(cell) / Math.max(1, rowCells.length)),
    colIndex: rowCells.indexOf(cell),
    rowKey: row?.dataset['rowKey'] ?? row?.id,
    colKey: cell.dataset['colKey'] ?? colKeyFromId(id),
  };
}

function cellAtPosition(
  root: HTMLElement,
  selection: Pick<SurfaceGridSelection, 'rowIndex' | 'colIndex'>,
  options: SurfaceGridBindingOptions,
): HTMLElement | null {
  const row = rows(root, options)[selection.rowIndex];
  if (!row) return null;
  return (
    rowCellsFor(row, cells(root, options), options)[selection.colIndex] ?? null
  );
}

function paintLocalSelection(
  root: HTMLElement,
  activeId: string,
  activeCell: HTMLElement,
  options: SurfaceGridBindingOptions,
): void {
  const activePosition = selectionForCell(root, activeCell, options);

  for (const cell of cells(root, options)) {
    const id = surfaceIdFor(cell);
    const selected = cell === activeCell || id === activeId;
    cell.dataset['runtimeSelected'] = selected ? 'true' : 'false';
    cell.dataset['selected'] = selected ? 'true' : 'false';
    cell.classList.toggle('is-runtime-selected', selected);
    cell.tabIndex = selected ? 0 : -1;
  }

  for (const [rowIndex, row] of rows(root, options).entries()) {
    const selected = activePosition.rowIndex === rowIndex;
    row.dataset['runtimeSelectedRow'] = selected ? 'true' : 'false';
    row.classList.toggle('is-runtime-selected-row', selected);
  }

  for (const header of columnHeaders(root)) {
    const selected =
      activePosition.colKey !== undefined &&
      header.dataset['colKey'] === activePosition.colKey;
    header.dataset['runtimeSelectedCol'] = selected ? 'true' : 'false';
    header.classList.toggle('is-runtime-selected-col', selected);
  }
}

function nextCellForKey(
  root: HTMLElement,
  current: HTMLElement,
  event: KeyboardEvent,
  options: SurfaceGridBindingOptions,
  cache?: SurfaceDomBindingCache,
): HTMLElement | null {
  const allCells = cells(root, options, cache);
  const currentIndex = allCells.indexOf(current);
  if (currentIndex < 0) return allCells[0] ?? null;
  const row = current.closest<HTMLElement>(
    options.rowSelector ?? DEFAULT_ROW_SELECTOR,
  );
  const rowCells = row ? rowCellsFor(row, allCells, options, cache) : [];
  const allRows = rows(root, options, cache);
  const rowIndex = row ? allRows.indexOf(row) : -1;
  const colIndex = rowCells.indexOf(current);
  const columns = Math.max(
    1,
    rowCells.length || inferredColumnCount(root, allCells, options, cache),
  );
  let nextIndex = currentIndex;

  switch (event.key) {
    case 'ArrowUp':
      nextIndex = Math.max(0, currentIndex - columns);
      break;
    case 'ArrowDown':
      nextIndex = Math.min(allCells.length - 1, currentIndex + columns);
      break;
    case 'ArrowLeft':
      if (rowCells.length && colIndex > 0) {
        return rowCells[colIndex - 1] ?? current;
      }
      nextIndex = currentIndex;
      break;
    case 'ArrowRight':
      if (rowCells.length && colIndex >= 0 && colIndex < rowCells.length - 1) {
        return rowCells[colIndex + 1] ?? current;
      }
      nextIndex = currentIndex;
      break;
    case 'Home':
      if (event.ctrlKey || event.metaKey) return allCells[0] ?? current;
      if (rowCells.length) return rowCells[0] ?? current;
      nextIndex = Math.floor(currentIndex / columns) * columns;
      break;
    case 'End':
      if (event.ctrlKey || event.metaKey)
        return allCells[allCells.length - 1] ?? current;
      if (rowCells.length) return rowCells[rowCells.length - 1] ?? current;
      nextIndex = Math.min(
        allCells.length - 1,
        Math.floor(currentIndex / columns) * columns + columns - 1,
      );
      break;
    case 'PageUp':
      nextIndex = Math.max(0, currentIndex - columns * 10);
      break;
    case 'PageDown':
      nextIndex = Math.min(allCells.length - 1, currentIndex + columns * 10);
      break;
    case 'Tab':
      nextIndex = event.shiftKey
        ? Math.max(0, currentIndex - 1)
        : Math.min(allCells.length - 1, currentIndex + 1);
      break;
  }

  if (
    rowIndex >= 0 &&
    colIndex >= 0 &&
    (event.key === 'ArrowUp' || event.key === 'ArrowDown')
  ) {
    const nextRow =
      allRows[event.key === 'ArrowUp' ? rowIndex - 1 : rowIndex + 1];
    const nextRowCell = nextRow
      ? rowCellsFor(nextRow, allCells, options, cache)[colIndex]
      : null;
    if (nextRowCell) return nextRowCell;
  }

  return allCells[nextIndex] ?? current;
}

function inferredColumnCount(
  root: HTMLElement,
  allCells: HTMLElement[],
  options: SurfaceGridBindingOptions,
  cache?: SurfaceDomBindingCache,
): number {
  const firstRow = rows(root, options, cache)[0];
  if (!firstRow) return allCells.length || 1;
  return rowCellsFor(firstRow, allCells, options, cache).length || 1;
}

function colKeyFromId(id: string): string | undefined {
  const match = /^c-[^-]+-(.+)$/.exec(id);
  return match?.[1];
}

function focusCell(cell: HTMLElement, reveal: boolean): void {
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

function isVisible(element: HTMLElement): boolean {
  return element.offsetParent !== null || element.getClientRects().length > 0;
}

export default surfaceGridBinding;
