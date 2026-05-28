// Focus ladder — the cross-host coordination primitive that gives
// every surface-compatible app the same focus / selection / keyboard
// semantics, regardless of which host package (boxel-grid,
// boxel-canvas, future siblings) draws the chrome.
//
// THE PROBLEM
// ===========
//
// Today, focus + selection live in two unrelated places:
//   - boxel-grid has CellFocusResource — a single (row, col) head
//     plus an anchor for shift-extend, scoped to ONE grid.
//   - boxel-canvas defers to xyflow's node-selection state — a flat
//     set of selected node ids, scoped to ONE canvas viewport.
// Neither knows about the other. Neither knows about NESTED focus
// (focus the row card → enter → focus a field inside it). Neither
// shares keyboard handling.
//
// The result: every host reimplements the focus state machine, and
// composite hosts (a canvas containing rows, each containing cells)
// have to glue two unrelated systems together by hand.
//
// THE MODEL
// =========
//
// One TREE per surface root. Each node has:
//   - id            stable string (host-chosen)
//   - surface       what kind of node it is (canvas | grid | row | frame |
//                   layout | cell | run)
//   - parentId      where it sits in the tree (null for the root)
//
// Hosts REGISTER nodes as components mount, UNREGISTER on teardown.
// Sibling order is the registration order, or set explicitly via
// setSiblings (for hosts that own column reordering, list shuffling,
// etc.).
//
// Focus is a PATH down the tree: ["canvas", "row-i1", "field-name"].
// The deepest entry is the focused id; the path's length is the focus
// depth. Selection is a Set per depth — moving deeper preserves the
// outer selection, so "node row-i1 is selected at canvas depth" stays
// true while focus is INSIDE that row card.
//
// Keyboard is a thin translator: KeyboardEvent → ladder method. Hosts
// install the handler on their surface root; the ladder doesn't
// touch the DOM.
//
// LIFETIME
// ========
//
// One FocusLadder per surface root (one per Canvas, one per Grid).
// For composite apps (Canvas containing Grids, or vice versa), one
// per OUTERMOST surface — the inner surfaces register their nodes
// with the outer ladder.
//
// Hosts construct it, hold a reference, expose it to children via
// context. K.3a (this file) is pure logic; K.3b wires hosts.

import { tracked } from '@glimmer/tracking';

import type { FociGridCoordinate, FociNodePolicy } from './foci-store.ts';
import type { Surface } from './widget.ts';

// ─── topology types ──────────────────────────────────────────────

/**
 * The ladder works in terms of a small subset of `Surface` — the
 * surfaces that participate in focus/selection nesting. `pane` and
 * `plane` are lift surfaces; they live in their own focus subtree
 * (the lift handles its own focus root) and don't appear here.
 *
 * Hierarchy goes `space → layout/canvas/scene/grid/scroll/flow/outline →
 * row/frame/pane/plane → cell/run/unit`. The ladder accepts the full
 * declared surface vocabulary so examples can exercise ergonomics before
 * every pair has a hardened contract shard.
 *
 * `connection` is a first-class object surface for edges/links between
 * objects. It participates in selection, drag/connection editing, and
 * coordinate-space movement instead of being host-only SVG/path chrome.
 *
 * `unit` is the bottom of most trees (single-value widget). `cell`
 * sits between `layout` and `unit` only for multi-unit widgets.
 */
export type LadderSurface = Surface;

export type Target =
  | 'structure'
  | 'chrome'
  | 'object'
  | 'field'
  | 'value'
  | 'range-item'
  | 'action'
  | 'debug';

export type TargetScope = 'document' | 'range' | 'object' | 'actions' | 'debug';

export type TargetMode = 'use' | 'change' | 'inspect' | 'debug';

export interface LadderRegistration {
  /** Stable id, host-chosen. Must be unique across the ladder. */
  id: string;
  /** Stable product identity. Used to preserve focus when the same
   *  database-bound thing is rendered by a different surface form
   *  across mode changes, e.g. `Run(field)` -> `Cell(field)`. */
  focusKey?: string;
  surface: LadderSurface;
  /** Selection/navigation target role. Coordinates are exhaustive;
   *  target roles define the purposeful projection users navigate. */
  target?: Target;
  /** Optional scope this surface introduces for target behavior. */
  targetScope?: TargetScope;
  /** Explicit runtime scope override. Prefer presets/targets first. */
  scopeId?: string;
  /** Explicit runtime scope kind override. Prefer presets/targets first. */
  scopeKind?: TargetScope;
  /** Runtime policy facts used by SurfaceRuntime. Ladder keeps these opaque. */
  policy?: FociNodePolicy;
  /** Optional grid coordinate for engine-owned sheet movement and ranges. */
  grid?: FociGridCoordinate;
  /** Owning coordinate-space id, when this node participates in one. */
  coordinateSpaceId?: string;
  /** Local coordinate inside the owning coordinate space. */
  localCoordinate?: unknown;
  /** Parent id, or `null` for the surface root. */
  parentId: string | null;
}

interface LadderNode extends LadderRegistration {}

export interface LadderNodeSnapshot extends LadderRegistration {
  depth: number;
  children: readonly string[];
  focused: boolean;
  hovered: boolean;
  onFocusPath: boolean;
  selected: boolean;
}

// ─── selection / nav types ───────────────────────────────────────

/** Which axis a step request applies to. Hosts that lay out children
 *  in a row pass `'x'`; column-stack hosts pass `'y'`; agnostic hosts
 *  (Tab key, sequential nav) pass `'linear'`. K.3a treats all axes
 *  uniformly; K.4+ may add axis-specific behavior (e.g., a grid
 *  treating ArrowDown vs ArrowRight differently). */
export type LadderAxis = 'x' | 'y' | 'linear';

export interface LadderSelectOptions {
  /** Cmd/Ctrl semantics — toggle the id in the selection set without
   *  clearing the rest. */
  additive?: boolean;
  /** Shift semantics — extend the selection from the active anchor
   *  to the given id (inclusive sibling range). Falls back to a
   *  single-cell selection when no anchor is set. */
  range?: boolean;
}

// ─── the ladder ──────────────────────────────────────────────────

/**
 * Cross-host focus + selection coordination. See the file header for
 * the model.
 *
 * The two state slots (`_focusPath`, `_selection`) are `@tracked` so
 * Glimmer templates that read `isFocused(id)` / `isSelected(id)`
 * / `focusedId` / `focusDepth` re-render on change. All mutations
 * REASSIGN those slots (never mutate in place), so trackers fire
 * reliably.
 *
 * The class is plain (not a Resource) because its lifetime is tied
 * to the host's surface root, not to a set of arguments — hosts
 * construct it once.
 */
export class FocusLadder {
  // Topology — id → node, parent → ordered children.
  // Untracked: hosts mutate via register/unregister, and consumers
  // observe via the tracked focus/selection state (which gates the
  // re-render). Direct topology reads (childrenOf, getNode) are for
  // host code; templates should consume focus/selection.
  private _nodes = new Map<string, LadderNode>();
  private _children = new Map<string | null, string[]>();

  @tracked private _focusPath: readonly string[] = [];
  @tracked private _selection: ReadonlyMap<number, ReadonlySet<string>> =
    new Map();
  @tracked private _hoveredId: string | null = null;
  private _pendingFocusKey: string | null = null;
  private _restoredFocusId: string | null = null;

  // Anchor for shift-extend at the current focus depth. Untracked —
  // an implementation detail of `select(..., { range: true })`.
  private _selectionAnchor: string | null = null;

  // Subscribers fired after every mutation that changes topology,
  // focus, hover, or selection state. Used by hosts that need to
  // mirror ladder state into their own data model (e.g., `<Canvas>`
  // mirroring ladder clears into xyflow's `selected` flag on nodes)
  // and by coordinate tools that need the live registered tree.
  // Each sub gets the ladder as its argument so it can read whatever
  // it needs.
  private _subs = new Set<(ladder: FocusLadder) => void>();

  // ─── topology ──────────────────────────────────────────────

  /**
   * Register a node. Returns an unregister function — hosts SHOULD
   * call it on teardown (typically from a `willDestroy` hook or a
   * Glimmer modifier's cleanup).
   *
   * Re-registering an existing id refreshes its surface/parent fields
   * and (if the parent changed) re-parents it in the sibling map.
   */
  register(reg: LadderRegistration): () => void {
    const existing = this._nodes.get(reg.id);
    const registered = { ...reg };
    this._nodes.set(reg.id, registered);
    if (!existing || existing.parentId !== reg.parentId) {
      if (existing) this._removeFromSiblings(reg.id, existing.parentId);
      const sibs = this._children.get(reg.parentId)?.slice() ?? [];
      if (!sibs.includes(reg.id)) sibs.push(reg.id);
      this._children.set(reg.parentId, sibs);
    }
    if (
      this._pendingFocusKey !== null &&
      this._focusKeyForNode(registered) === this._pendingFocusKey
    ) {
      this._pendingFocusKey = null;
      this._restoredFocusId = reg.id;
      this.focusId(reg.id);
    } else {
      this._notify();
    }
    return () => {
      if (this._nodes.get(reg.id) === registered) {
        this.unregister(reg.id);
      }
    };
  }

  /** Unregister a node. Drops it from the focus path and selection
   *  if present. Children of the dropped node are NOT cascaded —
   *  hosts that own a subtree should unregister bottom-up. */
  unregister(id: string): void {
    const node = this._nodes.get(id);
    if (!node) return;
    const focusedNode = this.focusedId ? this._nodes.get(this.focusedId) : null;
    if (focusedNode && this._focusPath.includes(id)) {
      this._pendingFocusKey = this._focusKeyForNode(focusedNode);
    }
    this._nodes.delete(id);
    this._removeFromSiblings(id, node.parentId);
    if (this._focusPath.includes(id)) {
      const idx = this._focusPath.indexOf(id);
      this._focusPath = this._focusPath.slice(0, idx);
    }
    let mutated = false;
    const next = new Map<number, Set<string>>();
    for (const [depth, set] of this._selection) {
      if (set.has(id)) {
        const cloned = new Set(set);
        cloned.delete(id);
        if (cloned.size > 0) next.set(depth, cloned);
        mutated = true;
      } else {
        next.set(depth, new Set(set));
      }
    }
    if (mutated) {
      this._selection = next;
    }
    if (this._selectionAnchor === id) this._selectionAnchor = null;
    if (this._hoveredId === id) {
      this._hoveredId = null;
    }
    if (
      this._pendingFocusKey !== null &&
      this._focusFirstByKey(this._pendingFocusKey)
    ) {
      this._pendingFocusKey = null;
    }
    this._notify();
  }

  /** Replace the ordered sibling list under a parent. Use when the
   *  host owns reordering (e.g., grid columns dragged into a new
   *  position) and needs to keep the ladder's nav order in sync. */
  setSiblings(parentId: string | null, ids: string[]): void {
    this._children.set(parentId, [...ids]);
    this._notify();
  }

  /** Clear ALL topology + state. Useful for hot-reload or surface
   *  swaps. */
  reset(): void {
    this._nodes.clear();
    this._children.clear();
    this._focusPath = [];
    this._selection = new Map();
    this._hoveredId = null;
    this._selectionAnchor = null;
    this._pendingFocusKey = null;
    this._restoredFocusId = null;
    this._notify();
  }

  // ─── subscribe ─────────────────────────────────────────────

  /**
   * Register a callback fired after every topology / focus / hover /
   * selection mutation.
   * Returns an unsubscribe function. Hosts use this to mirror ladder
   * state into their own data model (e.g., the `<Canvas>` host
   * mirroring `ladder.clear()` into xyflow's `unselectAll()` so the
   * two selection models stay in sync).
   *
   * Subs run synchronously during the mutating call. Don't mutate
   * the ladder from inside a sub — that re-enters and can cause
   * loops; if you need to chain effects, queue them with
   * `requestAnimationFrame` or similar.
   *
   * Topology changes (register / unregister / setSiblings) notify
   * because coordinate debuggers, decals, and keyboard projections need
   * to see the complete live tree, not just focus state changes.
   */
  subscribe(cb: (ladder: FocusLadder) => void): () => void {
    this._subs.add(cb);
    return () => {
      this._subs.delete(cb);
    };
  }

  private _notify(): void {
    for (const cb of this._subs) cb(this);
  }

  private _removeFromSiblings(id: string, parentId: string | null): void {
    const sibs = this._children.get(parentId);
    if (!sibs) return;
    const idx = sibs.indexOf(id);
    if (idx < 0) return;
    const next = sibs.slice();
    next.splice(idx, 1);
    if (next.length === 0) this._children.delete(parentId);
    else this._children.set(parentId, next);
  }

  private _focusKeyForNode(node: LadderNode): string {
    return node.focusKey ?? node.id;
  }

  private _focusFirstByKey(focusKey: string): boolean {
    for (const node of this._nodes.values()) {
      if (this._focusKeyForNode(node) === focusKey) {
        this._restoredFocusId = node.id;
        this.focusId(node.id);
        return true;
      }
    }
    return false;
  }

  private _targetForNode(node: LadderNode): Target {
    if (node.target) return node.target;

    switch (node.surface) {
      case 'space':
      case 'layout':
      case 'scroll':
      case 'flow':
      case 'outline':
      case 'pane':
      case 'plane':
      case 'grid':
      case 'row':
      case 'scene':
      case 'canvas':
        return 'structure';
      case 'frame':
      case 'connection':
        return 'object';
      case 'cell':
        return 'field';
      case 'run':
      case 'unit':
        return 'value';
      default:
        return 'debug';
    }
  }

  private _isEligibleTarget(node: LadderNode, mode: TargetMode): boolean {
    const target = this._targetForNode(node);
    if (mode === 'debug') return true;
    if (this._isCollapsedIntoRangeItem(node, mode)) return false;

    switch (mode) {
      case 'use':
        return target === 'action';
      case 'change':
        return (
          target === 'field' ||
          target === 'value' ||
          target === 'range-item' ||
          target === 'object' ||
          target === 'action'
        );
      case 'inspect':
        return (
          target === 'object' ||
          target === 'field' ||
          target === 'value' ||
          target === 'range-item' ||
          target === 'action'
        );
      default:
        return false;
    }
  }

  private _rangeItemAncestorFor(node: LadderNode): LadderNode | null {
    let cursor: LadderNode | undefined = node;
    while (cursor?.parentId) {
      cursor = this._nodes.get(cursor.parentId);
      if (!cursor) return null;
      if (this._targetForNode(cursor) === 'range-item') return cursor;
    }
    return null;
  }

  private _isCollapsedIntoRangeItem(
    node: LadderNode,
    mode: TargetMode,
  ): boolean {
    if (mode !== 'change' && mode !== 'inspect') return false;
    const target = this._targetForNode(node);
    if (target !== 'field' && target !== 'value') return false;
    return this._rangeItemAncestorFor(node) !== null;
  }

  // ─── readers ───────────────────────────────────────────────

  /** The current focus path. Empty when nothing is focused. */
  get focusPath(): readonly string[] {
    return this._focusPath;
  }

  /** The deepest id on the focus path, or `null`. */
  get focusedId(): string | null {
    return this._focusPath[this._focusPath.length - 1] ?? null;
  }

  /** The stable product identity for the focused surface, when one was
   *  provided. Falls back to the surface id for anonymous surfaces. */
  get focusedKey(): string | null {
    const focusedId = this.focusedId;
    if (!focusedId) return null;
    const node = this._nodes.get(focusedId);
    return node ? this._focusKeyForNode(node) : focusedId;
  }

  /** The depth of the focused id (1 = root, 2 = root's child, ...).
   *  Returns 0 when nothing is focused. */
  get focusDepth(): number {
    return this._focusPath.length;
  }

  get hoveredId(): string | null {
    return this._hoveredId;
  }

  isFocused = (id: string): boolean => this.focusedId === id;

  isHovered = (id: string): boolean => this._hoveredId === id;

  /** True when `id` is anywhere on the focus path (including the
   *  deepest entry). Useful for "ancestor of focus" highlighting. */
  isOnFocusPath = (id: string): boolean => this._focusPath.includes(id);

  isSelected = (id: string): boolean => {
    const depth = this._depthOf(id);
    if (depth < 0) return false;
    return this._selection.get(depth)?.has(id) ?? false;
  };

  /** All selected ids at a given depth, in sibling order. */
  selectionAt(depth: number): readonly string[] {
    const set = this._selection.get(depth);
    if (!set) return [];
    const parentId = this._parentOfDepth(depth);
    const sibs = this._children.get(parentId) ?? [];
    return sibs.filter((id) => set.has(id));
  }

  /** Look up a node by id. Returns the registration record or `null`. */
  getNode(id: string): LadderRegistration | null {
    return this._nodes.get(id) ?? null;
  }

  targetFor(id: string): Target {
    const node = this._nodes.get(id);
    return node ? this._targetForNode(node) : 'debug';
  }

  targetScopeFor(id: string): TargetScope | undefined {
    return this._nodes.get(id)?.targetScope;
  }

  isEligibleTarget(id: string, mode: TargetMode = 'inspect'): boolean {
    const node = this._nodes.get(id);
    return node ? this._isEligibleTarget(node, mode) : false;
  }

  /** Resolve a raw coordinate/instance id to the closest purposeful
   *  target in the same ancestry chain for the requested mode. */
  targetIdFor(id: string | null, mode: TargetMode = 'inspect'): string | null {
    if (!id) return null;
    if (mode === 'debug') return this._nodes.has(id) ? id : null;
    let node = this._nodes.get(id);
    if (node && this._isCollapsedIntoRangeItem(node, mode)) {
      return this._rangeItemAncestorFor(node)?.id ?? null;
    }
    while (node) {
      if (this._isEligibleTarget(node, mode)) return node.id;
      if (node.parentId === null) break;
      node = this._nodes.get(node.parentId);
    }
    return null;
  }

  firstTargetId(mode: TargetMode = 'inspect'): string | null {
    return this._flattenTargetTree(mode)[0] ?? null;
  }

  lastTargetId(mode: TargetMode = 'inspect'): string | null {
    const ids = this._flattenTargetTree(mode);
    return ids[ids.length - 1] ?? null;
  }

  nextTargetInTree(id: string, mode: TargetMode = 'inspect'): string | null {
    return this._stepTargetInTree(id, +1, mode);
  }

  prevTargetInTree(id: string, mode: TargetMode = 'inspect'): string | null {
    return this._stepTargetInTree(id, -1, mode);
  }

  firstChildTargetId(id: string, mode: TargetMode = 'inspect'): string | null {
    const visit = (parentId: string): string | null => {
      for (const childId of this._children.get(parentId) ?? []) {
        const child = this._nodes.get(childId);
        if (!child) continue;
        if (this._isEligibleTarget(child, mode)) return child.id;
        const descendant = visit(child.id);
        if (descendant) return descendant;
      }
      return null;
    };
    return visit(id);
  }

  parentTargetId(id: string, mode: TargetMode = 'inspect'): string | null {
    let node = this._nodes.get(id);
    while (node?.parentId) {
      node = this._nodes.get(node.parentId);
      if (node && this._isEligibleTarget(node, mode)) return node.id;
    }
    return null;
  }

  selectedIds(): readonly string[] {
    const ids: string[] = [];
    for (const [depth] of this._selection) {
      ids.push(...this.selectionAt(depth));
    }
    return ids;
  }

  treeSnapshot(
    parentId: string | null = null,
    depth = 0,
  ): LadderNodeSnapshot[] {
    const snapshots: LadderNodeSnapshot[] = [];
    for (const id of this._children.get(parentId) ?? []) {
      const node = this._nodes.get(id);
      if (!node) continue;
      const children = this._children.get(id) ?? [];
      snapshots.push({
        ...node,
        depth,
        children,
        focused: this.isFocused(id),
        hovered: this.isHovered(id),
        onFocusPath: this.isOnFocusPath(id),
        selected: this.isSelected(id),
      });
      snapshots.push(...this.treeSnapshot(id, depth + 1));
    }
    return snapshots;
  }

  /** Consume the id restored by focus-key continuity. DOM modifiers use
   *  this once to return real browser focus after a mode-render swap. */
  consumeRestoredFocusId(id: string): boolean {
    if (this._restoredFocusId !== id) return false;
    this._restoredFocusId = null;
    return true;
  }

  /** Ordered child ids for a given parent (or the root when `parentId`
   *  is `null`). */
  childrenOf(parentId: string | null): readonly string[] {
    return this._children.get(parentId) ?? [];
  }

  /** The registered parent id for a node, or `null` for the root. */
  parentOf(id: string): string | null {
    return this._nodes.get(id)?.parentId ?? null;
  }

  /** Ordered sibling ids for a node, including the node itself. */
  siblingsOf(id: string): readonly string[] {
    const node = this._nodes.get(id);
    if (!node) return [];
    return this._children.get(node.parentId) ?? [];
  }

  /** Focus a registered node by id, rebuilding the full ancestry path. */
  focusId(id: string): boolean {
    if (!this._nodes.has(id)) return false;
    this.focus(this._ancestry(id));
    return true;
  }

  /** First registered surface in tree order. */
  firstId(): string | null {
    return this._flattenTree()[0] ?? null;
  }

  /** Last registered surface in tree order. */
  lastId(): string | null {
    const ids = this._flattenTree();
    return ids[ids.length - 1] ?? null;
  }

  /** DFS tree walk for Tab: first child, next sibling, then ancestor's
   *  next sibling. Mirrors the original polymorph surface traversal. */
  nextInTree(id: string): string | null {
    const kids = this._children.get(id) ?? [];
    if (kids.length > 0) return kids[0]!;

    let cur: string | null = id;
    while (cur) {
      const node = this._nodes.get(cur);
      if (!node) break;
      const sibs = this._children.get(node.parentId) ?? [];
      const idx = sibs.indexOf(cur);
      if (idx >= 0 && idx < sibs.length - 1) return sibs[idx + 1]!;
      cur = node.parentId;
    }
    return null;
  }

  /** Shift+Tab tree walk: previous sibling's deepest descendant, else
   *  parent. Mirrors the original polymorph surface traversal. */
  prevInTree(id: string): string | null {
    const node = this._nodes.get(id);
    if (!node) return null;
    const sibs = this._children.get(node.parentId) ?? [];
    const idx = sibs.indexOf(id);
    if (idx > 0) {
      let cur = sibs[idx - 1]!;
      // eslint-disable-next-line no-constant-condition
      while (true) {
        const kids = this._children.get(cur) ?? [];
        if (kids.length === 0) return cur;
        cur = kids[kids.length - 1]!;
      }
    }
    return node.parentId;
  }

  // ─── focus nav ─────────────────────────────────────────────

  /**
   * Set the focus path explicitly. The selection at the deepest depth
   * is replaced with `{focusedId}`; outer depths are preserved (so a
   * canvas-level selection survives entering a row card). Pass an
   * empty array to clear focus entirely.
   */
  focus(path: readonly string[]): void {
    this._focusPath = [...path];
    const head = this.focusedId;
    if (head === null) {
      this._selectionAnchor = null;
      this._notify();
      return;
    }
    const depth = this._focusPath.length - 1;
    const next = new Map<number, Set<string>>();
    for (const [d, set] of this._selection) {
      if (d !== depth) next.set(d, new Set(set));
    }
    next.set(depth, new Set([head]));
    this._selection = next;
    this._selectionAnchor = head;
    this._notify();
  }

  /** Descend into the focused node's first child. Returns true if
   *  focus moved. */
  enter(): boolean {
    const head = this.focusedId;
    if (!head) return false;
    const kids = this._children.get(head);
    if (!kids || kids.length === 0) return false;
    this.focus([...this._focusPath, kids[0]!]);
    return true;
  }

  /** Pop the deepest entry off the focus path. Returns true if focus
   *  moved (i.e., depth was > 0). */
  exit(): boolean {
    if (this._focusPath.length === 0) return false;
    this.focus(this._focusPath.slice(0, -1));
    return true;
  }

  /** Move focus to the next sibling at the current depth. The `axis`
   *  hint lets hosts wire ArrowRight to `'x'`, ArrowDown to `'y'`,
   *  Tab to `'linear'`. K.3a treats all axes the same; K.4+ may
   *  add axis-specific behavior. */
  next(axis: LadderAxis = 'linear'): boolean {
    if (!this.focusedId) return false;
    return this._step(+1, axis);
  }

  prev(axis: LadderAxis = 'linear'): boolean {
    if (!this.focusedId) return false;
    return this._step(-1, axis);
  }

  private _step(delta: 1 | -1, _axis: LadderAxis): boolean {
    const head = this.focusedId;
    if (!head) return false;
    const node = this._nodes.get(head);
    if (!node) return false;
    const sibs = this._children.get(node.parentId) ?? [];
    const idx = sibs.indexOf(head);
    if (idx < 0) return false;
    const target = idx + delta;
    if (target < 0 || target >= sibs.length) return false;
    const nextId = sibs[target]!;
    this.focus([...this._focusPath.slice(0, -1), nextId]);
    return true;
  }

  private _flattenTree(): string[] {
    const out: string[] = [];
    const visit = (parentId: string | null): void => {
      const kids = this._children.get(parentId) ?? [];
      for (const id of kids) {
        out.push(id);
        visit(id);
      }
    };
    visit(null);
    return out;
  }

  private _flattenTargetTree(mode: TargetMode): string[] {
    if (mode === 'debug') return this._flattenTree();
    return this._flattenTree().filter((id) => {
      const node = this._nodes.get(id);
      return node ? this._isEligibleTarget(node, mode) : false;
    });
  }

  private _stepTargetInTree(
    id: string,
    delta: 1 | -1,
    mode: TargetMode,
  ): string | null {
    const current = this.targetIdFor(id, mode);
    const ids = this._flattenTargetTree(mode);
    if (ids.length === 0) return null;
    if (!current) return delta > 0 ? ids[0]! : ids[ids.length - 1]!;
    const index = ids.indexOf(current);
    if (index < 0) return delta > 0 ? ids[0]! : ids[ids.length - 1]!;
    return ids[index + delta] ?? null;
  }

  // ─── selection ─────────────────────────────────────────────

  /**
   * Update selection at the focused id's depth. Focus moves to `id`
   * (so subsequent shift-extend operations anchor correctly), unless
   * an additive toggle removes `id` — in that case focus stays put.
   *
   * - Plain (no opts):     replace with `{id}`. Anchor = id.
   * - `additive: true`:    toggle `id` in the set. Anchor = id.
   * - `range: true`:       extend from the active anchor to `id`
   *                        (inclusive sibling range). Anchor preserved.
   *                        Falls back to a single-cell selection when
   *                        no anchor is set or anchor and id have
   *                        different parents.
   */
  select(id: string, opts: LadderSelectOptions = {}): void {
    const node = this._nodes.get(id);
    if (!node) return;
    const depth = this._depthOf(id);
    if (depth < 0) return;
    const next = new Map<number, Set<string>>();
    for (const [d, set] of this._selection) {
      next.set(d, new Set(set));
    }
    let bucket = next.get(depth) ?? new Set<string>();

    if (opts.range && this._selectionAnchor !== null) {
      const anchorNode = this._nodes.get(this._selectionAnchor);
      if (anchorNode && anchorNode.parentId === node.parentId) {
        const sibs = this._children.get(node.parentId) ?? [];
        const fromIdx = sibs.indexOf(this._selectionAnchor);
        const toIdx = sibs.indexOf(id);
        if (fromIdx >= 0 && toIdx >= 0) {
          const [lo, hi] =
            fromIdx <= toIdx ? [fromIdx, toIdx] : [toIdx, fromIdx];
          bucket = new Set(sibs.slice(lo, hi + 1));
        } else {
          bucket = new Set([id]);
        }
      } else {
        bucket = new Set([id]);
        this._selectionAnchor = id;
      }
    } else if (opts.additive) {
      bucket = new Set(bucket);
      if (bucket.has(id)) bucket.delete(id);
      else bucket.add(id);
      this._selectionAnchor = id;
    } else {
      bucket = new Set([id]);
      this._selectionAnchor = id;
    }

    if (bucket.size === 0) next.delete(depth);
    else next.set(depth, bucket);
    this._selection = next;
    if (bucket.has(id)) {
      this._focusPath = this._ancestry(id);
    }
    this._notify();
  }

  /** Clear selection at a given depth, or all depths. When called
   *  with no depth, ALSO clears the focus path — that's the
   *  "user clicked the background, drop everything" idiom. When
   *  called with a depth, focus is preserved. */
  clear(depth?: number): void {
    if (depth === undefined) {
      this._selection = new Map();
      this._selectionAnchor = null;
      this._focusPath = [];
      this._hoveredId = null;
      this._notify();
      return;
    }
    const next = new Map<number, Set<string>>();
    for (const [d, set] of this._selection) {
      if (d !== depth) next.set(d, new Set(set));
    }
    this._selection = next;
    this._notify();
  }

  /** Clear focus, hover, anchor, and selected ids for one subtree.
   *  This is the local Escape idiom for composite surfaces: a grid or
   *  canvas can drop its own visible selection chrome without forcing
   *  the surrounding card/environment to handle the same key event. */
  clearSubtree(parentId: string): boolean {
    if (!this._nodes.has(parentId)) return false;

    const ids = new Set<string>();
    const collect = (id: string): void => {
      ids.add(id);
      for (const childId of this._children.get(id) ?? []) {
        collect(childId);
      }
    };
    collect(parentId);

    let changed = false;
    const nextSelection = new Map<number, Set<string>>();
    for (const [depth, set] of this._selection) {
      const nextSet = new Set<string>();
      for (const id of set) {
        if (ids.has(id)) {
          changed = true;
        } else {
          nextSet.add(id);
        }
      }
      if (nextSet.size > 0) nextSelection.set(depth, nextSet);
    }

    const focusIndex = this._focusPath.findIndex((id) => ids.has(id));
    if (focusIndex >= 0) {
      this._focusPath = this._focusPath.slice(0, focusIndex);
      changed = true;
    }

    if (this._selectionAnchor && ids.has(this._selectionAnchor)) {
      this._selectionAnchor = null;
      changed = true;
    }

    if (this._hoveredId && ids.has(this._hoveredId)) {
      this._hoveredId = null;
      changed = true;
    }

    if (!changed) return false;
    this._selection = nextSelection;
    this._notify();
    return true;
  }

  hoverId(id: string | null): void {
    if (id !== null && !this._nodes.has(id)) return;
    if (this._hoveredId === id) return;
    this._hoveredId = id;
    this._notify();
  }

  // ─── keyboard ──────────────────────────────────────────────

  /**
   * Handle a keyboard event. Returns true (and calls preventDefault)
   * when the event mapped to a ladder op; false to let the host
   * handle it (e.g., printable keys for type-to-edit).
   *
   * Mapping:
   *   ArrowDown / ArrowRight  →  next (y / x)
   *   ArrowUp   / ArrowLeft   →  prev (y / x)
   *   Tab                     →  next (linear); Shift+Tab → prev
   *   Enter                   →  enter
   *   Escape                  →  exit
   *
   * Shift modifier with arrows is reserved for range-extend in K.4;
   * for now it's treated like plain arrow.
   */
  handleKey(event: KeyboardEvent): boolean {
    let moved = false;
    switch (event.key) {
      case 'ArrowDown':
        moved = this.next('y');
        break;
      case 'ArrowUp':
        moved = this.prev('y');
        break;
      case 'ArrowRight':
        moved = this.next('x');
        break;
      case 'ArrowLeft':
        moved = this.prev('x');
        break;
      case 'Tab':
        moved = event.shiftKey ? this.prev('linear') : this.next('linear');
        break;
      case 'Enter':
        moved = this.enter();
        break;
      case 'Escape':
        moved = this.exit();
        break;
      default:
        return false;
    }
    if (moved) event.preventDefault();
    return moved;
  }

  // ─── private helpers ───────────────────────────────────────

  /** Walk the ancestry chain to find the depth of a node. Root = 0,
   *  root's child = 1, etc. Returns -1 if the node isn't registered. */
  private _depthOf(id: string): number {
    let node = this._nodes.get(id);
    if (!node) return -1;
    let depth = 0;
    while (node && node.parentId !== null) {
      const parent = this._nodes.get(node.parentId);
      if (!parent) break;
      depth++;
      node = parent;
    }
    return depth;
  }

  /** Build the path of ids from the root down to (and including) `id`. */
  private _ancestry(id: string): readonly string[] {
    const chain: string[] = [];
    let node = this._nodes.get(id);
    while (node) {
      chain.unshift(node.id);
      if (node.parentId === null) break;
      node = this._nodes.get(node.parentId);
    }
    return chain;
  }

  /** The parent id at a given depth on the current focus path. Used
   *  by `selectionAt` to find the sibling list for ordering. */
  private _parentOfDepth(depth: number): string | null {
    if (depth <= 0) return null;
    return this._focusPath[depth - 1] ?? null;
  }
}

/**
 * Convenience factory. K.3a callers construct one explicitly; K.3b
 * will add a context-provided variant for hosts that want
 * auto-resolution from a parent.
 */
export function createFocusLadder(): FocusLadder {
  return new FocusLadder();
}
