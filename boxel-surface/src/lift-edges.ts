import { tracked } from '@glimmer/tracking';
import type { ComponentLike } from '@glint/template';

import type { LadderSurface } from './focus-ladder.ts';
import type { LiftKind } from './contracts.ts';
import type {
  LiftBackdrop,
  LiftElevation,
  LiftKeyboardModel,
  LiftPlacement,
  LiftSize,
} from './components/lift.gts';

export const LiftContextName = 'boxel-surface:lift-manager';

export type LiftOpen =
  | 'inspect-hover'
  | 'inspect-activate'
  | 'change-hover'
  | 'change-activate'
  | 'use-action';

export interface LiftEdgeDeclaration {
  presentation?: string;
  open?: LiftOpen | LiftOpen[];
  placementMode?: LiftPlacement;
  size?: LiftSize;
  backdrop?: LiftBackdrop;
  elevation?: LiftElevation;
  keyboard?: LiftKeyboardModel;
  affordance?: 'auto' | 'chevron' | 'none';
}

export type SurfaceLiftEdgeInput = boolean | string | LiftEdgeDeclaration;

export type LiftEdges = Partial<Record<LiftKind, SurfaceLiftEdgeInput>>;

export interface LiftSource {
  id: string;
  path?: string;
  surface: LadderSurface;
  element: HTMLElement;
  data?: unknown;
}

export interface LiftEdge extends LiftEdgeDeclaration {
  kind: LiftKind;
  sourceId: string;
  sourcePath?: string;
  sourceSurface: LadderSurface;
  presentation: string;
  open: LiftOpen[];
}

export interface LiftTargetContext {
  source: LiftSource;
  edge: LiftEdge;
  close: () => void;
  escalate: (kind: LiftKind) => void;
  updateSourceData: (data: unknown) => void;
}

export type LiftTargetComponent = ComponentLike<{
  Args: {
    context: LiftTargetContext;
  };
}>;

export interface LiftResolvedTarget {
  component: LiftTargetComponent;
}

export type LiftResolver = (
  context: LiftTargetContext,
) => LiftResolvedTarget | LiftTargetComponent | null | undefined;

interface ActiveLift {
  source: LiftSource;
  edge: LiftEdge;
  focusToken: number;
}

interface RegisteredLiftSource {
  source: LiftSource;
  edges: LiftEdges | undefined;
  token: symbol;
}

interface SourceAriaSnapshot {
  element: HTMLElement;
  expanded: string | null;
  controls: string | null;
  describedBy: string | null;
  hasPopup: string | null;
  editing: string | null;
  hadEditingClass: boolean;
}

function defaultOpenFor(kind: LiftKind): LiftOpen[] {
  switch (kind) {
    case 'details':
    case 'preview':
      return ['inspect-hover'];
    case 'edit':
      return ['change-activate'];
    case 'tools':
      return ['use-action'];
  }
}

function normalizeOpen(
  kind: LiftKind,
  open: LiftEdgeDeclaration['open'],
): LiftOpen[] {
  if (Array.isArray(open)) return open;
  if (open) return [open];
  return defaultOpenFor(kind);
}

function normalizeEdge(
  source: LiftSource,
  edges: LiftEdges | undefined,
  kind: LiftKind,
): LiftEdge | null {
  const input = edges?.[kind];
  if (!input) return null;

  const declaration: LiftEdgeDeclaration =
    input === true
      ? {}
      : typeof input === 'string'
        ? { presentation: input }
        : input;

  return {
    ...declaration,
    kind,
    sourceId: source.id,
    sourcePath: source.path,
    sourceSurface: source.surface,
    presentation: declaration.presentation ?? kind,
    open: normalizeOpen(kind, declaration.open),
  };
}

function escapeAttributeValue(value: string): string {
  return value.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

function restoreAttribute(
  element: HTMLElement,
  name: string,
  value: string | null,
): void {
  if (value === null) {
    element.removeAttribute(name);
  } else {
    element.setAttribute(name, value);
  }
}

interface LiftEditorFocusSnapshot {
  token: number;
  tagName: string;
  id: string | null;
  ariaLabel: string | null;
  index: number;
  selectionStart: number | null;
  selectionEnd: number | null;
}

function liftEditorSelector(): string {
  return [
    'input:not([type="hidden"]):not([disabled]):not([tabindex="-1"])',
    'textarea:not([disabled]):not([tabindex="-1"])',
    'select:not([disabled]):not([tabindex="-1"])',
    '[contenteditable=""]:not([tabindex="-1"])',
    '[contenteditable="true"]:not([tabindex="-1"])',
  ].join(',');
}

function captureLiftEditorFocus(
  token: number | undefined,
): LiftEditorFocusSnapshot | null {
  if (token === undefined) return null;
  const active = document.activeElement;
  if (!(active instanceof HTMLElement)) return null;
  const lift = active.closest<HTMLElement>('[data-bx-lift]');
  if (!lift || !active.matches(liftEditorSelector())) return null;
  const editors = Array.from(
    lift.querySelectorAll<HTMLElement>(liftEditorSelector()),
  );
  const index = Math.max(0, editors.indexOf(active));
  const selection =
    active instanceof HTMLInputElement || active instanceof HTMLTextAreaElement
      ? {
          selectionStart: active.selectionStart,
          selectionEnd: active.selectionEnd,
        }
      : { selectionStart: null, selectionEnd: null };
  return {
    token,
    tagName: active.tagName,
    id: active.id || null,
    ariaLabel: active.getAttribute('aria-label'),
    index,
    ...selection,
  };
}

function restoreLiftEditorFocus(
  snapshot: LiftEditorFocusSnapshot | null,
): void {
  if (!snapshot) return;
  const restore = (): void => {
    const lift = document.querySelector<HTMLElement>(
      `[data-bx-lift-focus-token="${snapshot.token}"]`,
    );
    if (!lift) return;
    const editors = Array.from(
      lift.querySelectorAll<HTMLElement>(liftEditorSelector()),
    );
    const active = document.activeElement;
    if (
      active instanceof HTMLElement &&
      lift.contains(active) &&
      active.matches(liftEditorSelector())
    ) {
      return;
    }
    let target: HTMLElement | undefined;
    if (snapshot.id) {
      target = editors.find((editor) => editor.id === snapshot.id);
    }
    if (!target && snapshot.ariaLabel) {
      target = editors.find(
        (editor) =>
          editor.tagName === snapshot.tagName &&
          editor.getAttribute('aria-label') === snapshot.ariaLabel,
      );
    }
    target ??= editors[snapshot.index] ?? editors[0];
    if (!target) return;
    target.focus({ preventScroll: true });
    if (
      (target instanceof HTMLInputElement ||
        target instanceof HTMLTextAreaElement) &&
      snapshot.selectionStart !== null &&
      snapshot.selectionEnd !== null
    ) {
      target.setSelectionRange(snapshot.selectionStart, snapshot.selectionEnd);
    }
  };
  requestAnimationFrame(restore);
  setTimeout(restore, 0);
}

export interface SurfaceLiftManagerOptions {
  hoverPauseMs?: number;
  dismissGraceMs?: number;
  dismissCooldownMs?: number;
}

export class LiftManager {
  @tracked private active: ActiveLift | null = null;

  resolver: LiftResolver | undefined;

  private sources = new Map<string, RegisteredLiftSource>();
  private hoverTimer: ReturnType<typeof setTimeout> | null = null;
  private dismissTimer: ReturnType<typeof setTimeout> | null = null;
  private lastClosedAt = 0;
  private hoverPauseMs: number;
  private dismissGraceMs: number;
  private dismissCooldownMs: number;
  private sourceAria: SourceAriaSnapshot | null = null;
  private nextFocusToken = 1;

  constructor(options: SurfaceLiftManagerOptions = {}) {
    this.hoverPauseMs = options.hoverPauseMs ?? 350;
    this.dismissGraceMs = options.dismissGraceMs ?? 220;
    this.dismissCooldownMs = options.dismissCooldownMs ?? 600;
  }

  get isOpen(): boolean {
    return this.active !== null && this.targetComponent !== undefined;
  }

  get activeSourceId(): string | undefined {
    return this.active?.source.id;
  }

  get activeTargetId(): string | undefined {
    if (!this.active) return undefined;
    return `lift:${this.active.edge.kind}:${this.active.source.id}`;
  }

  get kind(): LiftKind {
    return this.active?.edge.kind ?? 'details';
  }

  get anchorSelector(): string {
    const id = this.active?.source.id;
    return id ? `[data-ladder-id="${escapeAttributeValue(id)}"]` : '';
  }

  get placementMode(): LiftPlacement {
    return this.active?.edge.placementMode ?? 'attached';
  }

  get size(): LiftSize {
    return (
      this.active?.edge.size ??
      (this.kind === 'edit' ? 'comfortable' : 'compact')
    );
  }

  get backdrop(): LiftBackdrop {
    return this.active?.edge.backdrop ?? 'none';
  }

  get elevation(): LiftElevation {
    return this.active?.edge.elevation ?? 'elevated';
  }

  get keyboardModel(): LiftKeyboardModel {
    return (
      this.active?.edge.keyboard ??
      (this.kind === 'edit' ? 'edit-text' : 'pick')
    );
  }

  get focusToken(): number | undefined {
    return this.active?.focusToken;
  }

  get targetContext(): LiftTargetContext | undefined {
    if (!this.active) return undefined;
    return {
      source: this.active.source,
      edge: this.active.edge,
      close: this.close,
      escalate: this.escalate,
      updateSourceData: (data: unknown) => {
        if (!this.active) return;
        this.updateSourceData(this.active.source.id, data);
      },
    };
  }

  get resolvedTarget(): LiftResolvedTarget | undefined {
    const context = this.targetContext;
    if (!context || !this.resolver) return undefined;
    const resolved = this.resolver(context);
    if (!resolved) return undefined;
    if (typeof resolved === 'function') {
      return { component: resolved as LiftTargetComponent };
    }
    return resolved;
  }

  get targetComponent(): LiftTargetComponent | undefined {
    return this.resolvedTarget?.component;
  }

  get canRenderTarget(): boolean {
    return (
      this.targetComponent !== undefined && this.targetContext !== undefined
    );
  }

  hasEdge(
    source: LiftSource,
    edges: LiftEdges | undefined,
    kind: LiftKind,
  ): boolean {
    return normalizeEdge(source, edges, kind) !== null;
  }

  registerSource(source: LiftSource, edges: LiftEdges | undefined): () => void {
    const token = Symbol(source.id);
    this.sources.set(source.id, { source, edges, token });
    return () => {
      const current = this.sources.get(source.id);
      if (current?.token === token) {
        this.sources.delete(source.id);
      }
    };
  }

  isOpenFor(sourceId: string): boolean {
    return this.active?.source.id === sourceId;
  }

  updateSourceData(sourceId: string, data: unknown): void {
    const registered = this.sources.get(sourceId);
    if (registered) {
      this.sources.set(sourceId, {
        ...registered,
        source: {
          ...registered.source,
          data,
        },
      });
    }

    const active = this.active;
    if (!active || active.source.id !== sourceId) return;
    const focusSnapshot = captureLiftEditorFocus(active.focusToken);
    this.active = {
      ...active,
      source: {
        ...active.source,
        data,
      },
    };
    restoreLiftEditorFocus(focusSnapshot);
  }

  open = (
    source: LiftSource,
    edges: LiftEdges | undefined,
    kind: LiftKind,
  ): boolean => {
    const edge = normalizeEdge(source, edges, kind);
    if (!edge) return false;
    this.cancelHoverTimer();
    this.cancelDismissTimer();
    this.restoreSourceAria();
    this.active = { source, edge, focusToken: this.nextFocusToken++ };
    this.applySourceAria();
    return true;
  };

  openForMode = (
    source: LiftSource,
    edges: LiftEdges | undefined,
    mode: 'use' | 'change' | 'inspect',
    open: LiftOpen,
  ): boolean => {
    for (const kind of liftKindsForOpen(open)) {
      const edge = normalizeEdge(source, edges, kind);
      if (!edge || !edge.open.includes(open)) continue;
      if (open.startsWith('change') && mode !== 'change') continue;
      if (open.startsWith('inspect') && mode !== 'inspect') continue;
      if (open.startsWith('use') && mode !== 'use') continue;
      this.cancelHoverTimer();
      this.cancelDismissTimer();
      this.restoreSourceAria();
      this.active = { source, edge, focusToken: this.nextFocusToken++ };
      this.applySourceAria();
      return true;
    }
    return false;
  };

  openForModeBySourceId = (
    sourceId: string,
    mode: 'use' | 'change' | 'inspect',
    open: LiftOpen,
    sourceOverride: Partial<LiftSource> = {},
  ): boolean => {
    const registered = this.sources.get(sourceId);
    if (!registered) return false;
    return this.openForMode(
      { ...registered.source, ...sourceOverride },
      registered.edges,
      mode,
      open,
    );
  };

  scheduleHover = (
    source: LiftSource,
    edges: LiftEdges | undefined,
    mode: 'use' | 'change' | 'inspect',
  ): void => {
    const open: LiftOpen =
      mode === 'inspect'
        ? 'inspect-hover'
        : mode === 'change'
          ? 'change-hover'
          : 'use-action';
    const kind = liftKindsForOpen(open).find((candidate) => {
      const edge = normalizeEdge(source, edges, candidate);
      return edge?.open.includes(open);
    });
    if (!kind) return;
    if (this.active?.edge.kind === 'edit') return;
    if (
      this.lastClosedAt > 0 &&
      Date.now() - this.lastClosedAt < this.dismissCooldownMs
    ) {
      return;
    }
    this.cancelHoverTimer();
    this.cancelDismissTimer();
    this.hoverTimer = setTimeout(() => {
      this.hoverTimer = null;
      if (this.active?.edge.kind === 'edit') return;
      this.open(source, edges, kind);
    }, this.hoverPauseMs);
  };

  scheduleDismissDetails = (): void => {
    this.cancelHoverTimer();
    if (
      this.active?.edge.kind !== 'details' &&
      this.active?.edge.kind !== 'preview'
    ) {
      return;
    }
    this.cancelDismissTimer();
    this.dismissTimer = setTimeout(() => {
      this.dismissTimer = null;
      if (
        this.active?.edge.kind === 'details' ||
        this.active?.edge.kind === 'preview'
      ) {
        this.restoreSourceAria();
        this.active = null;
        this.lastClosedAt = Date.now();
      }
    }, this.dismissGraceMs);
  };

  cancelDismiss = (): void => {
    this.cancelDismissTimer();
  };

  escalate = (kind: LiftKind): void => {
    const active = this.active;
    if (!active) return;
    this.open(active.source, { [kind]: { presentation: kind } }, kind);
  };

  close = (): void => {
    const closedKind = this.active?.edge.kind;
    this.cancelHoverTimer();
    this.cancelDismissTimer();
    this.restoreSourceAria();
    this.active = null;
    if (closedKind === 'details' || closedKind === 'preview') {
      this.lastClosedAt = Date.now();
    }
  };

  destroy(): void {
    this.cancelHoverTimer();
    this.cancelDismissTimer();
    this.restoreSourceAria();
  }

  private applySourceAria(): void {
    if (!this.active || !this.activeTargetId) return;
    const { element } = this.active.source;
    this.sourceAria = {
      element,
      expanded: element.getAttribute('aria-expanded'),
      controls: element.getAttribute('aria-controls'),
      describedBy: element.getAttribute('aria-describedby'),
      hasPopup: element.getAttribute('aria-haspopup'),
      editing: element.getAttribute('data-surface-editing'),
      hadEditingClass: element.classList.contains('is-surface-editing'),
    };

    const targetId = this.activeTargetId;
    switch (this.active.edge.kind) {
      case 'details':
        element.setAttribute('aria-describedby', targetId);
        element.removeAttribute('aria-controls');
        element.removeAttribute('aria-haspopup');
        break;
      case 'preview':
      case 'edit':
        element.setAttribute('aria-controls', targetId);
        element.setAttribute('aria-haspopup', 'dialog');
        element.removeAttribute('aria-describedby');
        if (this.active.edge.kind === 'edit') {
          element.setAttribute('data-surface-editing', 'true');
          element.classList.add('is-surface-editing');
        }
        break;
      case 'tools':
        element.setAttribute('aria-controls', targetId);
        element.setAttribute('aria-haspopup', 'menu');
        element.removeAttribute('aria-describedby');
        break;
    }
    element.setAttribute('aria-expanded', 'true');
  }

  private restoreSourceAria(): void {
    const snapshot = this.sourceAria;
    if (!snapshot) return;
    this.sourceAria = null;
    restoreAttribute(snapshot.element, 'aria-expanded', snapshot.expanded);
    restoreAttribute(snapshot.element, 'aria-controls', snapshot.controls);
    restoreAttribute(
      snapshot.element,
      'aria-describedby',
      snapshot.describedBy,
    );
    restoreAttribute(snapshot.element, 'aria-haspopup', snapshot.hasPopup);
    restoreAttribute(
      snapshot.element,
      'data-surface-editing',
      snapshot.editing,
    );
    snapshot.element.classList.toggle(
      'is-surface-editing',
      snapshot.hadEditingClass,
    );
  }

  private cancelHoverTimer(): void {
    if (this.hoverTimer !== null) {
      clearTimeout(this.hoverTimer);
      this.hoverTimer = null;
    }
  }

  private cancelDismissTimer(): void {
    if (this.dismissTimer !== null) {
      clearTimeout(this.dismissTimer);
      this.dismissTimer = null;
    }
  }
}

function liftKindsForOpen(open: LiftOpen): LiftKind[] {
  switch (open) {
    case 'inspect-hover':
    case 'inspect-activate':
      return ['details', 'preview'];
    case 'change-hover':
      return ['details', 'preview'];
    case 'change-activate':
      return ['edit'];
    case 'use-action':
      return ['tools', 'preview', 'details'];
  }
}

export function createLiftManager(
  options: SurfaceLiftManagerOptions = {},
): LiftManager {
  return new LiftManager(options);
}
