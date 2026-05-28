import { modifier } from 'ember-modifier';

import type {
  FocusLadder,
  LadderNodeSnapshot,
  TargetMode,
} from '../focus-ladder.ts';
import type { SurfaceRuntime } from '../surface-runtime.ts';
import type { FociMode, FociProjection } from '../foci-store.ts';

export type CoordinateDebugView = 'all' | 'targets';

export interface CoordinateDebuggerOptions {
  enabled?: boolean;
  decals?: boolean;
  open?: boolean;
  runtime?: SurfaceRuntime;
  view?: CoordinateDebugView;
}

const StyleId = 'boxel-surface-coordinate-debugger-styles';

function ensureStyles(document: Document): void {
  if (document.getElementById(StyleId)) return;

  const style = document.createElement('style');
  style.id = StyleId;
  style.textContent = `
    .boxel-surface-coordinate-debugger {
      --surface-debug-accent: #5645d4;
      --surface-debug-hover: #0f766e;
      position: fixed;
      right: var(--boxel-surface-coordinate-debugger-right, 16px);
      top: var(--boxel-surface-coordinate-debugger-top, 16px);
      z-index: 100000;
      color: #111827;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
      font-size: 11px;
      line-height: 1.35;
      pointer-events: none;
      display: flex;
      flex-direction: column;
      align-items: flex-end;
    }

    .boxel-surface-coordinate-debugger__toggle,
    .boxel-surface-coordinate-debugger__row {
      pointer-events: auto;
      font: inherit;
    }

    .boxel-surface-coordinate-debugger__toggle {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-height: 30px;
      padding: 6px 10px;
      border: 1px solid rgba(17, 24, 39, 0.18);
      border-radius: 7px;
      background: rgba(255, 255, 255, 0.94);
      color: #111827;
      box-shadow: 0 10px 26px rgba(15, 23, 42, 0.16);
      cursor: pointer;
    }

    .boxel-surface-coordinate-debugger__panel {
      width: min(620px, calc(100vw - 32px));
      max-height: calc(100vh - var(--boxel-surface-coordinate-debugger-top, 16px) - 32px);
      margin-top: 8px;
      overflow: hidden;
      border: 1px solid rgba(17, 24, 39, 0.16);
      border-radius: 9px;
      background: rgba(255, 255, 255, 0.96);
      box-shadow: 0 18px 48px rgba(15, 23, 42, 0.22);
      pointer-events: auto;
      backdrop-filter: blur(10px);
      display: flex;
      flex-direction: column;
    }

    .boxel-surface-coordinate-debugger__panel[hidden] {
      display: none;
    }

    .boxel-surface-coordinate-debugger__header {
      display: grid;
      gap: 4px;
      padding: 10px 12px;
      border-bottom: 1px solid rgba(17, 24, 39, 0.1);
      background: #fafaf9;
      flex: 0 0 auto;
    }

    .boxel-surface-coordinate-debugger__title {
      font-weight: 700;
      font-size: 12px;
    }

    .boxel-surface-coordinate-debugger__stat {
      display: grid;
      grid-template-columns: 66px minmax(0, 1fr);
      gap: 8px;
      color: #4b5563;
      align-items: start;
    }

    .boxel-surface-coordinate-debugger__stat strong {
      color: #111827;
      font-weight: 700;
    }

    .boxel-surface-coordinate-debugger__value {
      min-width: 0;
      overflow-wrap: anywhere;
      white-space: normal;
    }

    .boxel-surface-coordinate-debugger__tree {
      min-height: 0;
      flex: 1 1 auto;
      overflow: auto;
      padding: 6px;
      overscroll-behavior: contain;
    }

    .boxel-surface-coordinate-debugger__row {
      width: 100%;
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: 8px;
      align-items: start;
      padding-top: 4px;
      padding-bottom: 4px;
      border: 0;
      border-radius: 5px;
      background: transparent;
      color: #111827;
      text-align: left;
      cursor: pointer;
    }

    .boxel-surface-coordinate-debugger__row:hover {
      background: rgba(86, 69, 212, 0.08);
    }

    .boxel-surface-coordinate-debugger__row[data-focus-path='true'] {
      background: rgba(86, 69, 212, 0.05);
    }

    .boxel-surface-coordinate-debugger__row[data-selected='true'] {
      background: rgba(86, 69, 212, 0.14);
      color: #24185f;
    }

    .boxel-surface-coordinate-debugger__row[data-hovered='true'] {
      box-shadow: inset 0 0 0 1px rgba(0, 117, 222, 0.36);
    }

    .boxel-surface-coordinate-debugger__row[data-editing='true'] {
      background: rgba(245, 215, 94, 0.4);
      box-shadow: inset 0 0 0 1px rgba(221, 91, 0, 0.3);
    }

    .boxel-surface-coordinate-debugger__coordinate {
      min-width: 0;
      overflow-wrap: anywhere;
      white-space: normal;
    }

    .boxel-surface-coordinate-debugger__surface {
      color: #6b7280;
      font-weight: 700;
    }

    .boxel-surface-coordinate-debugger__badge {
      color: #6b7280;
      font-size: 10px;
      white-space: nowrap;
      padding-top: 1px;
    }

    .boxel-surface-coordinate-decal {
      position: fixed;
      pointer-events: none;
      box-sizing: border-box;
      border: 2px solid transparent;
      border-radius: 5px;
      z-index: 99990;
      transform: translateZ(0);
    }

    .boxel-surface-coordinate-decal[hidden] {
      display: none;
    }

    .boxel-surface-coordinate-decal--selected {
      background: rgba(86, 69, 212, 0.055);
      box-shadow:
        inset 0 0 0 2px rgba(86, 69, 212, 0.58),
        0 0 0 1px rgba(255, 255, 255, 0.74),
        0 8px 22px rgba(86, 69, 212, 0.16);
    }

    .boxel-surface-coordinate-decal--hovered {
      border-color: rgba(13, 148, 136, 0.92);
      background: rgba(20, 184, 166, 0.075);
      box-shadow:
        0 0 0 1px rgba(240, 253, 250, 0.95),
        0 0 0 6px rgba(20, 184, 166, 0.2),
        0 12px 30px rgba(15, 118, 110, 0.24);
    }

    .boxel-surface-coordinate-decal--editing {
      background: rgba(245, 215, 94, 0.18);
      box-shadow:
        inset 0 0 0 2px rgba(221, 91, 0, 0.58),
        0 0 0 1px rgba(255, 255, 255, 0.74),
        0 8px 22px rgba(221, 91, 0, 0.14);
    }
  `;
  document.head.append(style);
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

function coordinateFor(node: LadderNodeSnapshot | null): string {
  return node?.focusKey ?? node?.id ?? 'none';
}

function isEnabledDataAttribute(value: string | null): boolean {
  return value === '' || value === 'true';
}

function targetModeForRoot(root: HTMLElement): TargetMode {
  const mode = root.getAttribute('data-surface-mode');
  const inspect = isEnabledDataAttribute(
    root.getAttribute('data-surface-inspect'),
  );
  if (mode === 'use' && inspect) return 'inspect';
  if (mode === 'use' || mode === 'change' || mode === 'inspect') return mode;
  return 'inspect';
}

function runtimeModeForTargetMode(mode: TargetMode): FociMode {
  return mode === 'debug' ? 'debug' : mode;
}

function text(value: string): Text {
  return document.createTextNode(value);
}

function appendStat(parent: HTMLElement, label: string, value: string): void {
  const row = document.createElement('div');
  row.className = 'boxel-surface-coordinate-debugger__stat';

  const strong = document.createElement('strong');
  strong.textContent = label;
  const content = document.createElement('span');
  content.className = 'boxel-surface-coordinate-debugger__value';
  content.textContent = value || 'none';
  content.title = value || 'none';

  row.append(strong, content);
  parent.append(row);
}

function applyDecal(
  decal: HTMLElement,
  root: HTMLElement,
  id: string | null,
): void {
  const target = surfaceElementById(root, id);
  if (!target || !target.isConnected) {
    decal.hidden = true;
    decal.removeAttribute('data-surface-coordinate-decal-id');
    decal.removeAttribute('data-surface-coordinate');
    return;
  }

  const rect = target.getBoundingClientRect();
  if (rect.width <= 0 || rect.height <= 0) {
    decal.hidden = true;
    decal.removeAttribute('data-surface-coordinate-decal-id');
    decal.removeAttribute('data-surface-coordinate');
    return;
  }

  decal.hidden = false;
  decal.setAttribute('data-surface-coordinate-decal-id', id ?? '');
  decal.setAttribute(
    'data-surface-coordinate',
    target.getAttribute('data-surface-coordinate') ?? '',
  );
  decal.style.left = `${Math.round(rect.left)}px`;
  decal.style.top = `${Math.round(rect.top)}px`;
  decal.style.width = `${Math.round(rect.width)}px`;
  decal.style.height = `${Math.round(rect.height)}px`;
}

const surfaceCoordinateDebugger = modifier<{
  Element: HTMLElement;
  Args: {
    Positional: [FocusLadder | undefined];
    Named: CoordinateDebuggerOptions;
  };
}>((element, [ladder], opts = {}) => {
  if (!ladder) return;

  const showPanel = opts.enabled ?? false;
  const showDecals = opts.decals ?? true;
  if (!showPanel && !showDecals) return;

  ensureStyles(document);

  let open = opts.open ?? false;
  let frame: number | undefined;
  let disposed = false;

  const host = showPanel ? document.createElement('div') : undefined;
  if (host) {
    host.className = 'boxel-surface-coordinate-debugger';
    host.setAttribute('data-surface-preserve-focus', '');
  }

  const toggle = showPanel ? document.createElement('button') : undefined;
  if (toggle) {
    toggle.type = 'button';
    toggle.className = 'boxel-surface-coordinate-debugger__toggle';
  }

  const panel = showPanel ? document.createElement('section') : undefined;
  if (panel) {
    panel.className = 'boxel-surface-coordinate-debugger__panel';
    panel.hidden = !open;
  }

  const selectedDecal = showDecals ? document.createElement('div') : undefined;
  if (selectedDecal) {
    selectedDecal.className =
      'boxel-surface-coordinate-decal boxel-surface-coordinate-decal--selected';
    selectedDecal.setAttribute('data-surface-coordinate-decal', 'selected');
  }

  const hoveredDecal = showDecals ? document.createElement('div') : undefined;
  if (hoveredDecal) {
    hoveredDecal.className =
      'boxel-surface-coordinate-decal boxel-surface-coordinate-decal--hovered';
    hoveredDecal.setAttribute('data-surface-coordinate-decal', 'hovered');
  }

  const editingDecal = showDecals ? document.createElement('div') : undefined;
  if (editingDecal) {
    editingDecal.className =
      'boxel-surface-coordinate-decal boxel-surface-coordinate-decal--editing';
    editingDecal.setAttribute('data-surface-coordinate-decal', 'editing');
  }

  if (host && toggle && panel) {
    host.append(toggle, panel);
    document.body.append(host);
  }
  if (selectedDecal && hoveredDecal && editingDecal) {
    document.body.append(selectedDecal, hoveredDecal, editingDecal);
  }

  const focusSurface = (id: string): void => {
    ladder.focusId(id);
    const target = surfaceElementById(element, id);
    target?.scrollIntoView({ block: 'nearest', inline: 'nearest' });
    target?.focus({ preventScroll: true });
  };

  const renderTree = (tree: LadderNodeSnapshot[]): HTMLElement => {
    const treeElement = document.createElement('div');
    treeElement.className = 'boxel-surface-coordinate-debugger__tree';

    for (const node of tree) {
      const surfaceElement = surfaceElementById(element, node.id);
      const isEditing =
        surfaceElement?.getAttribute('data-surface-editing') === 'true';
      const row = document.createElement('button');
      row.type = 'button';
      row.className = 'boxel-surface-coordinate-debugger__row';
      row.style.paddingLeft = `${8 + node.depth * 14}px`;
      row.setAttribute('data-selected', String(node.selected || node.focused));
      row.setAttribute('data-hovered', String(node.hovered));
      row.setAttribute('data-editing', String(isEditing));
      row.setAttribute('data-focus-path', String(node.onFocusPath));
      row.title = node.id;

      const coordinate = document.createElement('span');
      coordinate.className = 'boxel-surface-coordinate-debugger__coordinate';
      const surface = document.createElement('span');
      surface.className = 'boxel-surface-coordinate-debugger__surface';
      surface.textContent = node.surface;
      coordinate.append(surface, text(' '), text(coordinateFor(node)));

      const badges = document.createElement('span');
      badges.className = 'boxel-surface-coordinate-debugger__badge';
      badges.textContent = [
        node.target ?? '',
        node.targetScope ? `scope:${node.targetScope}` : '',
        node.focused ? 'focus' : '',
        node.selected ? 'select' : '',
        node.hovered ? 'hover' : '',
        isEditing ? 'edit' : '',
      ]
        .filter(Boolean)
        .join(' ');

      row.append(coordinate, badges);
      row.addEventListener('click', (event) => {
        event.preventDefault();
        event.stopPropagation();
        focusSurface(node.id);
      });
      treeElement.append(row);
    }

    return treeElement;
  };

  const render = (): void => {
    if (disposed) return;
    frame = undefined;

    const runtime = opts.runtime;
    const targetMode = targetModeForRoot(element);
    const projection: FociProjection | undefined = runtime?.projection({
      mode: runtimeModeForTargetMode(targetMode),
      inspect: isEnabledDataAttribute(
        element.getAttribute('data-surface-inspect'),
      ),
    });
    const allTree = ladder.treeSnapshot();
    const view = opts.view ?? 'all';
    const traversalIds = projection
      ? new Set(projection.traversal.ids)
      : undefined;
    const tree =
      view === 'targets'
        ? allTree.filter((node) =>
            traversalIds
              ? traversalIds.has(node.id)
              : ladder.isEligibleTarget(node.id, targetMode),
          )
        : allTree;
    const focused = ladder.focusedId ? ladder.getNode(ladder.focusedId) : null;
    const hovered = ladder.hoveredId ? ladder.getNode(ladder.hoveredId) : null;
    const selectedIds = ladder.selectedIds();
    const primary = projection?.visualPrimary;
    const selectedId =
      primary?.sourceId ??
      primary?.id ??
      ladder.focusedId ??
      selectedIds[selectedIds.length - 1] ??
      null;
    const hoveredId =
      projection?.visualDecals.find(
        (decal) => decal.kind === 'inspect' || decal.kind === 'hover',
      )?.ids[0] ?? ladder.hoveredId;
    const editingId =
      (primary?.kind === 'input'
        ? (primary.sourceId ?? primary.id)
        : undefined) ??
      allTree.find(
        (node) =>
          surfaceElementById(element, node.id)?.getAttribute(
            'data-surface-editing',
          ) === 'true',
      )?.id ??
      null;

    if (showPanel && toggle && panel) {
      toggle.textContent = open ? 'Coordinates - hide' : 'Coordinates';
      toggle.setAttribute('aria-expanded', String(open));
      panel.hidden = !open;

      const header = document.createElement('div');
      header.className = 'boxel-surface-coordinate-debugger__header';
      const title = document.createElement('div');
      title.className = 'boxel-surface-coordinate-debugger__title';
      title.textContent =
        view === 'targets'
          ? `Surface targets (${tree.length}/${allTree.length})`
          : `Surface coordinates (${allTree.length})`;
      header.append(title);
      appendStat(
        header,
        'view',
        view === 'targets' ? `targeting:${targetMode}` : 'all',
      );
      appendStat(header, 'runtime', runtime ? 'projection' : 'ladder');
      appendStat(
        header,
        'focus',
        focused ? (focused.focusKey ?? focused.id) : 'none',
      );
      appendStat(
        header,
        'hover',
        hovered ? (hovered.focusKey ?? hovered.id) : 'none',
      );
      appendStat(header, 'select', selectedIds.join(', ') || 'none');
      appendStat(header, 'edit', editingId ?? 'none');
      appendStat(header, 'path', ladder.focusPath.join(' -> ') || 'none');

      panel.replaceChildren(header, renderTree(tree));
    }

    if (selectedDecal && hoveredDecal && editingDecal) {
      applyDecal(selectedDecal, element, selectedId);
      applyDecal(hoveredDecal, element, hoveredId);
      applyDecal(editingDecal, element, editingId);
    }
  };

  const schedule = (): void => {
    if (frame !== undefined) return;
    frame = requestAnimationFrame(render);
  };

  const unsubscribe = ladder.subscribe(schedule);
  const unsubscribeRuntimeTopology = opts.runtime?.subscribeTopology(schedule);
  const unsubscribeRuntimeViewport = opts.runtime?.subscribeViewport(schedule);
  const observer = new MutationObserver(schedule);
  observer.observe(element, {
    subtree: true,
    childList: true,
    attributes: true,
    attributeFilter: [
      'data-ladder-id',
      'data-surface-coordinate',
      'data-surface-coordinate-ready',
      'data-surface-editing',
      'class',
      'style',
    ],
  });

  const onToggle = (event: MouseEvent): void => {
    event.preventDefault();
    event.stopPropagation();
    open = !open;
    render();
  };
  const onViewportChange = (): void => schedule();

  toggle?.addEventListener('click', onToggle);
  window.addEventListener('resize', onViewportChange);
  window.addEventListener('scroll', onViewportChange, true);
  render();

  return (): void => {
    disposed = true;
    if (frame !== undefined) cancelAnimationFrame(frame);
    unsubscribe();
    unsubscribeRuntimeTopology?.();
    unsubscribeRuntimeViewport?.();
    observer.disconnect();
    toggle?.removeEventListener('click', onToggle);
    window.removeEventListener('resize', onViewportChange);
    window.removeEventListener('scroll', onViewportChange, true);
    selectedDecal?.remove();
    hoveredDecal?.remove();
    editingDecal?.remove();
    host?.remove();
  };
});

export default surfaceCoordinateDebugger;
