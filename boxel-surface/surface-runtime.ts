import {
  createFociStore,
  type FociCancelOptions,
  type FociDispatchResult,
  type FociStore,
  type FociStoreSnapshot,
  type FociNodeRegistration,
  type FociProjection,
  type FociSelectOptions,
  type FociSemanticEvent,
  type FociTraversalOptions,
  type FociTraversalSet,
} from './foci-store.ts';

export interface SurfaceRuntimeUpdateOptions {
  preserveState?: boolean;
}

export type SurfaceRuntimeNotificationScope =
  | 'selection'
  | 'topology'
  | 'input'
  | 'viewport';
export type SurfaceRuntimeSubscriber = (runtime: SurfaceRuntime) => void;

export interface SurfaceRuntimeViewport {
  x: number;
  y: number;
  zoom: number;
  width: number;
  height: number;
}

export interface SurfaceRuntime {
  batch<T>(callback: () => T): T;
  beginBatch(): () => void;
  register(registration: FociNodeRegistration): () => void;
  update(id: string, patch: Partial<FociNodeRegistration>): void;
  unregister(id: string): void;
  setSiblings(parentId: string | null, ids: readonly string[]): void;
  reset(): void;

  dispatch(event: FociSemanticEvent): FociDispatchResult;
  projection(options?: FociTraversalOptions): FociProjection;
  traversalSet(options?: FociTraversalOptions): FociTraversalSet;
  snapshot(): FociStoreSnapshot;
  registrations(): readonly FociNodeRegistration[];
  node(id: string): FociNodeRegistration | null;
  readonly viewport: SurfaceRuntimeViewport;
  subscribe(callback: SurfaceRuntimeSubscriber): () => void;
  subscribeSelection(callback: SurfaceRuntimeSubscriber): () => void;
  subscribeTopology(callback: SurfaceRuntimeSubscriber): () => void;
  subscribeInput(callback: SurfaceRuntimeSubscriber): () => void;
  subscribeViewport(callback: SurfaceRuntimeSubscriber): () => void;

  focus(id: string | null): boolean;
  select(id: string, options?: FociSelectOptions): void;
  setViewport(viewport: Partial<SurfaceRuntimeViewport>): void;
  hover(id: string | null): FociDispatchResult;
  cancel(
    trigger?: FociCancelOptions['trigger'],
    options?: Omit<FociCancelOptions, 'trigger'>,
  ): FociDispatchResult;
  clearInteractionState(): void;
  clearSubtree(parentId: string): boolean;
}

interface RuntimeRecord extends FociNodeRegistration {}

interface InteractionState {
  focusedId: string | null;
  hoveredId: string | null;
  selections: readonly {
    headId: string | null;
    ids: readonly string[];
  }[];
}

interface PendingSelect {
  id: string;
  options: FociSelectOptions;
}

const ALL_NOTIFICATION_SCOPES: readonly SurfaceRuntimeNotificationScope[] = [
  'selection',
  'topology',
  'input',
  'viewport',
];
const INTERACTION_NOTIFICATION_SCOPES: readonly SurfaceRuntimeNotificationScope[] =
  ['selection', 'input'];
const TOPOLOGY_NOTIFICATION_SCOPES: readonly SurfaceRuntimeNotificationScope[] =
  ['topology', 'selection', 'input'];
const DEFAULT_VIEWPORT: SurfaceRuntimeViewport = {
  x: 0,
  y: 0,
  zoom: 1,
  width: 0,
  height: 0,
};

export class SurfaceRuntimeImpl implements SurfaceRuntime {
  private store: FociStore = createFociStore();
  private records = new Map<string, RuntimeRecord>();
  private siblingOrders = new Map<string | null, readonly string[]>();
  private subscribers = new Set<SurfaceRuntimeSubscriber>();
  private scopedSubscribers: Record<
    SurfaceRuntimeNotificationScope,
    Set<SurfaceRuntimeSubscriber>
  > = {
    selection: new Set(),
    topology: new Set(),
    input: new Set(),
    viewport: new Set(),
  };
  private viewportState: SurfaceRuntimeViewport = { ...DEFAULT_VIEWPORT };
  private pendingSelect: PendingSelect | null = null;
  private projectionCache = new Map<string, FociProjection>();
  private batchDepth = 0;
  private pendingReload = false;
  private pendingNotify = false;
  private pendingNotifyScopes = new Set<SurfaceRuntimeNotificationScope>();

  batch<T>(callback: () => T): T {
    const endBatch = this.beginBatch();
    try {
      return callback();
    } finally {
      endBatch();
    }
  }

  beginBatch(): () => void {
    let closed = false;
    this.batchDepth += 1;
    return () => {
      if (closed) return;
      closed = true;
      this.batchDepth = Math.max(0, this.batchDepth - 1);
      if (this.batchDepth === 0) this.flushBatch();
    };
  }

  register(registration: FociNodeRegistration): () => void {
    const record = cloneRegistration(registration);
    this.records.set(record.id, record);
    this.reloadAndNotify();

    return () => {
      if (this.records.get(record.id) === record) {
        this.unregister(record.id);
      }
    };
  }

  update(id: string, patch: Partial<FociNodeRegistration>): void {
    const existing = this.records.get(id);
    if (!existing) return;
    this.records.set(id, mergeRegistration(existing, patch));
    this.reloadAndNotify();
  }

  unregister(id: string): void {
    if (!this.records.delete(id)) return;
    for (const [parentId, order] of this.siblingOrders) {
      if (order.includes(id)) {
        this.siblingOrders.set(
          parentId,
          order.filter((orderedId) => orderedId !== id),
        );
      }
    }
    this.reloadAndNotify();
  }

  setSiblings(parentId: string | null, ids: readonly string[]): void {
    this.siblingOrders.set(parentId, [...ids]);
    this.reloadAndNotify();
  }

  reset(): void {
    this.records.clear();
    this.siblingOrders.clear();
    this.pendingSelect = null;
    this.pendingReload = false;
    this.pendingNotify = false;
    this.pendingNotifyScopes.clear();
    this.viewportState = { ...DEFAULT_VIEWPORT };
    this.projectionCache.clear();
    this.store.load([]);
    this.queueNotify(ALL_NOTIFICATION_SCOPES);
  }

  dispatch(event: FociSemanticEvent): FociDispatchResult {
    const previousSnapshotVersion = this.store.snapshotVersion;
    const result = this.store.dispatch(event);
    this.queueNotify(INTERACTION_NOTIFICATION_SCOPES, previousSnapshotVersion);
    return result;
  }

  projection(options: FociTraversalOptions = {}): FociProjection {
    const key = projectionCacheKey(options);
    const cached = this.projectionCache.get(key);
    if (cached) return cached;
    const projection = this.store.projection(options);
    this.projectionCache.set(key, projection);
    return projection;
  }

  traversalSet(options: FociTraversalOptions = {}): FociTraversalSet {
    return this.store.traversalSet(options);
  }

  snapshot(): FociStoreSnapshot {
    return this.store.snapshot();
  }

  registrations(): readonly FociNodeRegistration[] {
    return this.orderedRegistrations();
  }

  node(id: string): FociNodeRegistration | null {
    return this.store.node(id);
  }

  get viewport(): SurfaceRuntimeViewport {
    return { ...this.viewportState };
  }

  subscribe(callback: SurfaceRuntimeSubscriber): () => void {
    this.subscribers.add(callback);
    return () => this.subscribers.delete(callback);
  }

  subscribeSelection(callback: SurfaceRuntimeSubscriber): () => void {
    return this.subscribeScoped('selection', callback);
  }

  subscribeTopology(callback: SurfaceRuntimeSubscriber): () => void {
    return this.subscribeScoped('topology', callback);
  }

  subscribeInput(callback: SurfaceRuntimeSubscriber): () => void {
    return this.subscribeScoped('input', callback);
  }

  subscribeViewport(callback: SurfaceRuntimeSubscriber): () => void {
    return this.subscribeScoped('viewport', callback);
  }

  focus(id: string | null): boolean {
    const previousSnapshotVersion = this.store.snapshotVersion;
    const changed = this.store.focus(id);
    if (changed) this.queueNotify(['selection'], previousSnapshotVersion);
    return changed;
  }

  select(id: string, options: FociSelectOptions = {}): void {
    if (!this.records.has(id)) {
      this.pendingSelect = { id, options: { ...options } };
      return;
    }
    this.pendingSelect = null;
    if (this.pendingReload) {
      this.pendingSelect = { id, options: { ...options } };
      this.pendingNotify = true;
      this.pendingNotifyScopes.add('selection');
      this.projectionCache.clear();
      return;
    }
    const previousSnapshotVersion = this.store.snapshotVersion;
    this.store.select(id, options);
    this.queueNotify(['selection'], previousSnapshotVersion);
  }

  setViewport(viewport: Partial<SurfaceRuntimeViewport>): void {
    const next = normalizeViewport(
      {
        ...this.viewportState,
        ...viewport,
      },
      this.viewportState,
    );
    if (viewportsEqual(this.viewportState, next)) return;
    this.viewportState = next;
    this.queueNotify(['viewport']);
  }

  hover(id: string | null): FociDispatchResult {
    const previousSnapshotVersion = this.store.snapshotVersion;
    const result = this.store.hover(id);
    this.queueNotify(['selection'], previousSnapshotVersion);
    return result;
  }

  cancel(
    trigger: FociCancelOptions['trigger'] = 'programmatic',
    options: Omit<FociCancelOptions, 'trigger'> = {},
  ): FociDispatchResult {
    const previousSnapshotVersion = this.store.snapshotVersion;
    const result = this.store.cancel({ ...options, trigger });
    this.queueNotify(INTERACTION_NOTIFICATION_SCOPES, previousSnapshotVersion);
    return result;
  }

  clearInteractionState(): void {
    this.pendingSelect = null;
    const previousSnapshotVersion = this.store.snapshotVersion;
    this.store.clearInteractionState();
    this.queueNotify(INTERACTION_NOTIFICATION_SCOPES, previousSnapshotVersion);
  }

  clearSubtree(parentId: string): boolean {
    const ids = this.descendantIds(parentId);
    if (ids.size === 0) return false;

    const snapshot = this.store.snapshot();
    const focusInside = snapshot.focusPath.some((id) => ids.has(id));
    const selectionInside = Object.values(snapshot.selections).some(
      (selection) => selection.ids.some((id) => ids.has(id)),
    );
    const hoverInside =
      snapshot.hoveredId !== null && ids.has(snapshot.hoveredId);

    if (!focusInside && !selectionInside && !hoverInside) return false;

    // Phase 1 intentionally keeps ladder behavior authoritative. Until the
    // store has scoped selection clearing, dropping all mirrored runtime
    // interaction state is safer than preserving stale projection facts.
    const previousSnapshotVersion = this.store.snapshotVersion;
    this.store.clearInteractionState();
    this.queueNotify(INTERACTION_NOTIFICATION_SCOPES, previousSnapshotVersion);
    return true;
  }

  private reloadAndNotify(): void {
    this.projectionCache.clear();
    if (this.batchDepth > 0) {
      this.pendingReload = true;
      this.pendingNotify = true;
      for (const scope of TOPOLOGY_NOTIFICATION_SCOPES) {
        this.pendingNotifyScopes.add(scope);
      }
      return;
    }
    this.reload();
    this.notify(TOPOLOGY_NOTIFICATION_SCOPES);
  }

  private queueNotify(
    scopes: readonly SurfaceRuntimeNotificationScope[],
    previousSnapshotVersion?: number,
  ): void {
    if (
      previousSnapshotVersion !== undefined &&
      previousSnapshotVersion === this.store.snapshotVersion
    ) {
      return;
    }
    this.projectionCache.clear();
    if (this.batchDepth > 0) {
      this.pendingNotify = true;
      for (const scope of scopes) this.pendingNotifyScopes.add(scope);
      return;
    }
    this.notify(scopes);
  }

  private flushBatch(): void {
    if (this.pendingReload) {
      this.pendingReload = false;
      this.reload();
    }
    if (this.pendingNotify) {
      this.pendingNotify = false;
      const scopes =
        this.pendingNotifyScopes.size > 0
          ? [...this.pendingNotifyScopes]
          : [...ALL_NOTIFICATION_SCOPES];
      this.pendingNotifyScopes.clear();
      this.notify(scopes);
    }
  }

  private notify(scopes: readonly SurfaceRuntimeNotificationScope[]): void {
    this.projectionCache.clear();
    for (const subscriber of [...this.subscribers]) {
      subscriber(this);
    }
    const scoped = new Set<SurfaceRuntimeSubscriber>();
    for (const scope of scopes) {
      for (const subscriber of this.scopedSubscribers[scope]) {
        scoped.add(subscriber);
      }
    }
    for (const subscriber of scoped) {
      subscriber(this);
    }
  }

  private subscribeScoped(
    scope: SurfaceRuntimeNotificationScope,
    callback: SurfaceRuntimeSubscriber,
  ): () => void {
    const subscribers = this.scopedSubscribers[scope];
    subscribers.add(callback);
    return () => subscribers.delete(callback);
  }

  private reload(): void {
    this.projectionCache.clear();
    const state = captureInteractionState(this.store.snapshot());
    this.store.load(this.orderedRegistrations());
    restoreInteractionState(this.store, state, this.records);
    this.applyPendingSelect();
  }

  private applyPendingSelect(): void {
    const pending = this.pendingSelect;
    if (!pending || !this.records.has(pending.id)) return;
    this.pendingSelect = null;
    this.store.select(pending.id, pending.options);
  }

  private orderedRegistrations(): FociNodeRegistration[] {
    const children = new Map<string | null, RuntimeRecord[]>();
    for (const record of this.records.values()) {
      const siblings = children.get(record.parentId) ?? [];
      siblings.push(record);
      children.set(record.parentId, siblings);
    }

    for (const [parentId, order] of this.siblingOrders) {
      const siblings = children.get(parentId);
      if (!siblings) continue;
      const rank = new Map(order.map((id, index) => [id, index] as const));
      siblings.sort((a, b) => {
        const aRank = rank.get(a.id) ?? Number.MAX_SAFE_INTEGER;
        const bRank = rank.get(b.id) ?? Number.MAX_SAFE_INTEGER;
        if (aRank !== bRank) return aRank - bRank;
        return 0;
      });
    }

    const ordered: RuntimeRecord[] = [];
    const visit = (parentId: string | null): void => {
      for (const child of children.get(parentId) ?? []) {
        ordered.push(child);
        visit(child.id);
      }
    };
    visit(null);

    if (ordered.length !== this.records.size) {
      for (const record of this.records.values()) {
        if (!ordered.includes(record)) ordered.push(record);
      }
    }

    return ordered.map(cloneRegistration);
  }

  private descendantIds(parentId: string): Set<string> {
    const descendants = new Set<string>();
    const visit = (id: string): void => {
      if (!this.records.has(id) || descendants.has(id)) return;
      descendants.add(id);
      for (const record of this.records.values()) {
        if (record.parentId === id) visit(record.id);
      }
    };
    visit(parentId);
    return descendants;
  }
}

export function createSurfaceRuntime(): SurfaceRuntime {
  return new SurfaceRuntimeImpl();
}

function projectionCacheKey(options: FociTraversalOptions): string {
  return [
    options.mode ?? 'use',
    options.rootId ?? '',
    options.inspect === true ? 'inspect' : '',
    ...(options.aspects ?? []),
  ].join('\u0000');
}

function normalizeViewport(
  viewport: SurfaceRuntimeViewport,
  fallback: SurfaceRuntimeViewport = DEFAULT_VIEWPORT,
): SurfaceRuntimeViewport {
  return {
    x: finiteNumber(viewport.x, fallback.x),
    y: finiteNumber(viewport.y, fallback.y),
    zoom: positiveNumber(viewport.zoom, fallback.zoom),
    width: nonNegativeNumber(viewport.width, fallback.width),
    height: nonNegativeNumber(viewport.height, fallback.height),
  };
}

function viewportsEqual(
  a: SurfaceRuntimeViewport,
  b: SurfaceRuntimeViewport,
): boolean {
  return (
    a.x === b.x &&
    a.y === b.y &&
    a.zoom === b.zoom &&
    a.width === b.width &&
    a.height === b.height
  );
}

function finiteNumber(value: number, fallback: number): number {
  return Number.isFinite(value) ? value : fallback;
}

function positiveNumber(value: number, fallback: number): number {
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

function nonNegativeNumber(value: number, fallback: number): number {
  return Number.isFinite(value) && value >= 0 ? value : fallback;
}

function cloneRegistration<T extends FociNodeRegistration>(registration: T): T {
  return {
    ...registration,
    policy: registration.policy
      ? {
          ...registration.policy,
          aspects: registration.policy.aspects
            ? [...registration.policy.aspects]
            : undefined,
          accepts: registration.policy.accepts
            ? [...registration.policy.accepts]
            : undefined,
          modeProjection: registration.policy.modeProjection
            ? { ...registration.policy.modeProjection }
            : undefined,
          coordinateSpace: registration.policy.coordinateSpace
            ? {
                ...registration.policy.coordinateSpace,
                axes: registration.policy.coordinateSpace.axes
                  ? [...registration.policy.coordinateSpace.axes]
                  : undefined,
              }
            : undefined,
        }
      : undefined,
  };
}

function mergeRegistration(
  existing: RuntimeRecord,
  patch: Partial<FociNodeRegistration>,
): RuntimeRecord {
  return cloneRegistration({
    ...existing,
    ...patch,
    policy: patch.policy
      ? {
          ...(existing.policy ?? {}),
          ...patch.policy,
        }
      : existing.policy,
  });
}

function captureInteractionState(
  snapshot: FociStoreSnapshot,
): InteractionState {
  return {
    focusedId: snapshot.focusedId,
    hoveredId: snapshot.hoveredId,
    selections: Object.values(snapshot.selections).map((selection) => ({
      headId: selection.headId,
      ids: [...selection.ids],
    })),
  };
}

function restoreInteractionState(
  store: FociStore,
  state: InteractionState,
  records: ReadonlyMap<string, RuntimeRecord>,
): void {
  for (const selection of state.selections) {
    let first = true;
    for (const id of selection.ids) {
      if (!records.has(id)) continue;
      store.select(id, { additive: !first });
      first = false;
    }
    if (selection.headId && records.has(selection.headId)) {
      store.focus(selection.headId);
    }
  }

  if (state.focusedId && records.has(state.focusedId)) {
    store.focus(state.focusedId);
  }

  if (state.hoveredId && records.has(state.hoveredId)) {
    store.hover(state.hoveredId);
  }
}
