import type { LadderSurface, Target, TargetScope } from './focus-ladder.ts';
import {
  compileFociPolicy,
  compileFociProgram,
  type CompiledFociNode,
  type CompiledFociProgram,
} from './foci-policy.ts';

export type FociActivityRole =
  | 'input'
  | 'selection'
  | 'source'
  | 'origin'
  | 'destination'
  | 'preview'
  | 'context'
  | 'hover'
  | 'inspect';

export type FociVisualTier =
  | 'primary'
  | 'source'
  | 'destination'
  | 'context'
  | 'preview';

export type FociPointerPolicy =
  | 'preview-only'
  | 'surface-owned'
  | 'content-hover'
  | 'content-interactive'
  | 'cell-owned'
  | 'local-scroll'
  | 'transparent';

export type FociKeyboardPolicy =
  | 'tree'
  | 'grid-cell'
  | 'row-list'
  | 'outline'
  | 'editor'
  | 'canvas'
  | 'scene'
  | 'none';

export type FociMovementPolicy = 'auto' | 'engine' | 'surface';

export type FociSelectionPolicy =
  | 'none'
  | 'single'
  | 'multi'
  | 'range'
  | 'grid-cell'
  | 'row'
  | 'object';

export type FociEditPolicy = 'none' | 'inline' | 'lifted' | 'external';

export type FociLiftPolicy =
  | 'none'
  | 'hover-preview'
  | 'click'
  | 'dblclick'
  | 'enter'
  | 'tools';

export type FociChromePolicy =
  | 'full'
  | 'headerless'
  | 'chromeless'
  | 'bare'
  | 'inert'
  | 'containerless'
  | 'cell'
  | 'inline';

export type FociAdornmentPresentation =
  | 'auto'
  | 'surface'
  | 'decal'
  | 'both'
  | 'none';

export type FociMode = 'use' | 'change' | 'inspect' | 'debug';

export type FociPreset =
  | 'sheet'
  | 'grid'
  | 'table'
  | 'collection'
  | 'properties'
  | 'bare'
  | 'kanban'
  | 'dashboard'
  | 'canvas'
  | 'scene'
  | 'outline'
  | 'layout'
  | 'page'
  | 'notebook'
  | 'tools'
  | 'adorn';

export type FociPresetAspect =
  | 'sheet'
  | 'object'
  | 'cell'
  | 'menu'
  | 'bare'
  | 'reorder'
  | 'place'
  | 'resize'
  | 'connect'
  | 'tools'
  | 'inspect'
  | 'viewport';

export type FociCoordinateSpaceKind =
  | 'linear'
  | 'planar'
  | 'spatial'
  | 'spacetime'
  | 'graph';

export type FociSpaceMoveEffect =
  | 'preserve-input'
  | 'dismiss-input'
  | 'reanchor-overlay'
  | 'clear-selection';

export type FociCommitModel =
  | 'immediate'
  | 'draft'
  | 'preview'
  | 'continuous'
  | 'command';

export type FociCommitTrigger =
  | 'enter'
  | 'tab'
  | 'save'
  | 'blur'
  | 'change'
  | 'release'
  | 'explicit';

export type FociCancelTrigger =
  | 'escape'
  | 'outside-click'
  | 'click-away'
  | 'source-change'
  | 'programmatic';

export type FociTraversalPolicy = 'auto' | 'stop' | 'skip' | 'boundary';

export type FociTraversalModel = 'delegate' | 'document' | 'tools' | 'boundary';

export type FociTraversalAxis =
  | 'actions'
  | 'material'
  | 'editable'
  | 'receivers'
  | 'objects'
  | 'debug';

export type FociTraversalStopReason =
  | 'action'
  | 'interactive'
  | 'sheet-cell'
  | 'editable'
  | 'object'
  | 'row'
  | 'receiver'
  | 'inspect'
  | 'debug'
  | 'forced'
  | 'boundary'
  | 'document-item'
  | 'tool-control';

export interface FociCoordinateSpacePolicy {
  kind: FociCoordinateSpaceKind;
  axes?: readonly string[];
  moveEffect?: FociSpaceMoveEffect;
}

export type FociModeProjection = Partial<
  Record<FociMode, readonly FociPresetAspect[]>
>;

export type FociAdornmentPolicy = Partial<
  Record<FociProjectionAdornment, FociAdornmentPresentation>
>;

export type FociDecalShape = 'rect' | 'path' | 'none';

export interface FociNodePolicy {
  preset?: FociPreset;
  aspects?: readonly FociPresetAspect[];
  modeProjection?: FociModeProjection;
  traversal?: FociTraversalPolicy;
  traversalModel?: FociTraversalModel;
  chrome?: FociChromePolicy;
  selection?: FociSelectionPolicy;
  keyboard?: FociKeyboardPolicy;
  movement?: FociMovementPolicy;
  pointer?: FociPointerPolicy;
  edit?: FociEditPolicy;
  lift?: FociLiftPolicy;
  adornments?: FociAdornmentPolicy;
  decalShape?: FociDecalShape;
  actions?: 'none' | 'inside' | 'outside' | 'floating' | 'side-panel';
  coordinateSpace?: FociCoordinateSpacePolicy;
  commitModel?: FociCommitModel;
  commitTriggers?: readonly FociCommitTrigger[];
  cancelTriggers?: readonly FociCancelTrigger[];
  accepts?: readonly string[];
  payloadType?: string;
}

export interface FociGridCoordinate {
  row: number;
  col: number;
}

export interface FociNodeRegistration {
  id: string;
  parentId: string | null;
  surface: LadderSurface;
  target?: Target;
  targetScope?: TargetScope;
  focusKey?: string;
  scopeId?: string;
  scopeKind?: TargetScope;
  policy?: FociNodePolicy;
  grid?: FociGridCoordinate;
  coordinateSpaceId?: string;
  localCoordinate?: unknown;
}

export interface FociNodeSnapshot extends FociNodeRegistration {
  children: readonly string[];
  focusPath: boolean;
  focused: boolean;
  hovered: boolean;
  selected: boolean;
}

export interface FociRangeSnapshot {
  axis: 'linear' | 'grid' | 'spatial' | 'tree';
  start: unknown;
  end: unknown;
  normalized: unknown;
}

export interface FociSelectionSnapshot {
  scopeId: string;
  scopeKind: TargetScope;
  headId: string | null;
  anchorId: string | null;
  ids: readonly string[];
  range?: FociRangeSnapshot;
}

export interface FociActivityLayerSnapshot {
  role: FociActivityRole;
  id: string;
  sourceId?: string;
  scopeId?: string;
  keyOwner: boolean;
  visualTier: FociVisualTier;
}

export interface FociInputSession {
  kind: 'editor' | 'control' | 'menu' | 'tools' | 'drag' | 'connect';
  /**
   * Stable session id retained for existing consumers. This is also the
   * keyboard owner for current first-class input sessions.
   */
  id: string;
  /** Surface or generated lift/control target that owns input for this session. */
  targetId: string;
  sourceId: string | null;
  /** Generated lifted presentation id when input has moved out of the source tree. */
  liftedTargetId?: string;
  /** Node/session that should receive keyboard intent while the session is active. */
  keyboardOwnerId: string;
  /** How the source selection should visually quiet while input owns focus. */
  visualSuppression: FociInputVisualSuppressionPolicy;
  commitPolicy: FociInputCommitPolicy;
  cancelPolicy: FociInputCancelPolicy;
}

export type FociInputVisualSuppressionPolicy =
  | 'none'
  | 'source-anchor'
  | 'transfer-lock';

export interface FociInputCommitPolicy {
  model: FociCommitModel;
  triggers: readonly FociCommitTrigger[];
}

export interface FociInputCancelPolicy {
  triggers: readonly FociCancelTrigger[];
  restoreSource: boolean;
}

export interface FociOverlaySession {
  kind: 'preview' | 'edit' | 'details' | 'menu' | 'toolbar' | 'tools';
  sourceId: string;
  targetId: string;
  logicalParentId: string;
  activityRole: 'preview' | 'input' | 'context';
  autofocus: boolean;
  boundaryScopeId: string;
  coordinateSpaceId?: string;
  coordinateRevision?: number;
  placement:
    | 'top'
    | 'top-start'
    | 'top-end'
    | 'bottom'
    | 'bottom-start'
    | 'bottom-end'
    | 'side'
    | 'panel';
  focusPolicy: 'none' | 'contained' | 'trapped' | 'restore-source';
  closePolicy: 'escape' | 'outside-click' | 'source-change' | 'explicit';
}

export interface FociDestinationSnapshot {
  targetId: string;
  targetKind:
    | 'insert-before'
    | 'insert-after'
    | 'replace'
    | 'append'
    | 'drop'
    | 'drop-world'
    | 'drop-rect'
    | 'dashboard-slot'
    | 'grid-span'
    | 'kanban-gap'
    | 'lane-end'
    | 'connect-handle'
    | 'disconnect'
    | 'reorder-well'
    | 'nest-child';
  accepts: readonly string[];
  operation?: 'move' | 'copy' | 'link' | 'embed' | 'reorder' | 'connect';
}

export interface FociTransferSnapshot {
  kind: 'copy' | 'cut' | 'drag' | 'place' | 'connect' | 'resize' | 'reorder';
  origin: FociSelectionSnapshot;
  destination?: FociDestinationSnapshot;
  sourceHandleId?: string | null;
  targetHandleId?: string | null;
  pointerCaptured?: boolean;
  movedPastThreshold?: boolean;
}

export interface FociStoreSnapshot {
  focusPath: readonly string[];
  focusedId: string | null;
  hoveredId: string | null;
  activeScopeId: string | null;
  selections: Record<string, FociSelectionSnapshot>;
  layers: readonly FociActivityLayerSnapshot[];
  input: FociInputSession | null;
  overlay: FociOverlaySession | null;
  transfer: FociTransferSnapshot | null;
  coordinateRevisions: Record<string, number>;
  tree: readonly FociNodeSnapshot[];
  log: readonly string[];
}

export interface FociDispatchResult {
  handled: boolean;
  ownerId: string | null;
  reason: string;
  intent?: FociDispatchIntent;
  reveal?: FociRevealIntent;
}

export type FociMoveDirection = 'left' | 'right' | 'up' | 'down';

export type FociMoveAxis = 'linear' | 'grid' | 'spatial';

export type FociRevealPlacement = 'nearest' | 'center' | 'none';

export interface FociRevealIntent {
  targetId: string;
  block: FociRevealPlacement;
  inline: FociRevealPlacement;
  reason: 'keyboard' | 'programmatic' | 'initial';
}

export type FociDispatchIntent =
  | {
      type: 'open-editor';
      sourceId: string;
      editorId: string;
      editPolicy: FociEditPolicy;
      seed?: string;
    }
  | {
      type: 'commit-editor';
      sourceId: string | null;
      direction: 'up' | 'down';
    }
  | {
      type: 'commit-input';
      sourceId: string | null;
      targetId: string;
      trigger: FociCommitTrigger;
      advance: 'none' | 'up' | 'down';
    }
  | {
      type: 'open-menu';
      sourceId: string;
      targetId: string;
    }
  | {
      type: 'focus-control';
      targetId: string;
      sourceId: string | null;
    }
  | {
      type: 'drill-in';
      targetId: string;
    }
  | {
      type: 'drop-on-focus';
      sourceId: string | null;
      targetId: string | null;
    }
  | {
      type: 'move-selection';
      sourceId: string;
      targetId: string;
      direction: FociMoveDirection;
      axis: FociMoveAxis;
      range: boolean;
      scopeId: string;
    }
  | {
      type: 'resolve-move';
      ownerId: string;
      sourceId: string;
      direction: FociMoveDirection;
      axis: FociMoveAxis;
      range: boolean;
      scopeId: string;
    }
  | {
      type: 'go-up-level';
      sourceScopeId: string;
      targetScopeId: string | null;
      focusId: string | null;
    }
  | {
      type: 'dismiss-selection';
      scopeId: string;
      focusId: string | null;
    };

export interface FociTraversalOptions {
  mode?: FociMode;
  aspects?: readonly FociPresetAspect[];
  rootId?: string | null;
  inspect?: boolean;
}

export interface FociTraversalStop {
  id: string;
  surface: LadderSurface;
  target?: Target;
  scopeId: string;
  reason: FociTraversalStopReason;
}

export interface FociTraversalSet {
  mode: FociMode;
  axes: readonly FociTraversalAxis[];
  aspects: readonly FociPresetAspect[];
  rootId: string | null;
  ids: readonly string[];
  stops: readonly FociTraversalStop[];
}

export type FociProjectionAdornment =
  | 'focus'
  | 'range'
  | 'selection'
  | 'source'
  | 'origin'
  | 'destination'
  | 'context'
  | 'receiver'
  | 'hover'
  | 'inspect'
  | 'edit-anchor';

export type FociVisualAdornment = FociProjectionAdornment;

export interface FociProjectionVisualPrimary {
  kind:
    | 'input'
    | 'transfer-destination'
    | 'transfer-origin'
    | 'inspect'
    | 'range'
    | 'focus';
  id: string;
  sourceId?: string;
}

export interface FociProjectionNode {
  id: string;
  surface: LadderSurface;
  target?: Target;
  focusKey?: string;
  scopeId: string;
  traversalStop: boolean;
  traversalReason?: FociTraversalStopReason;
  selectable: boolean;
  editable: boolean;
  receiver: boolean;
  browserFocusable: boolean;
  programmaticFocusable: boolean;
  tabIndex: 0 | -1 | null;
  focusPath: boolean;
  focused: boolean;
  hovered: boolean;
  selected: boolean;
  layerRoles: readonly FociActivityRole[];
  adornments: readonly FociProjectionAdornment[];
  visualAdornments: readonly FociVisualAdornment[];
  surfaceAdornments: readonly FociVisualAdornment[];
  decalAdornments: readonly FociProjectionAdornment[];
  adornmentPresentation: Readonly<
    Partial<Record<FociProjectionAdornment, FociAdornmentPresentation>>
  >;
  suppressedAdornments: readonly FociProjectionAdornment[];
  decalShape?: FociDecalShape;
}

export interface FociProjectionDecal {
  kind: FociProjectionAdornment;
  ids: readonly string[];
  label: string;
}

export interface FociProjection {
  mode: FociMode;
  traversal: FociTraversalSet;
  nodes: readonly FociProjectionNode[];
  nodeMap: ReadonlyMap<string, FociProjectionNode>;
  decals: readonly FociProjectionDecal[];
  visualDecals: readonly FociProjectionDecal[];
  suppressedDecals: readonly FociProjectionDecal[];
  visualPrimary: FociProjectionVisualPrimary | null;
}

export type FociSemanticEvent =
  | ({ type: 'click'; targetId: string } & ClickOptions)
  | { type: 'hover'; targetId: string | null }
  | ({ type: 'key'; key: string } & KeyOptions)
  | ({ type: 'move'; direction: FociMoveDirection } & KeyOptions)
  | ({ type: 'activate' } & KeyOptions)
  | ({ type: 'edit'; seed?: string } & KeyOptions)
  | ({ type: 'commitInput' } & FociCommitOptions)
  | ({ type: 'escape' } & KeyOptions)
  | ({ type: 'cancel' } & FociCancelOptions)
  | { type: 'copy' }
  | { type: 'paste' }
  | { type: 'dragStart'; targetId: string }
  | { type: 'dragOver'; targetId: string }
  | { type: 'drop' }
  | { type: 'connectStart'; sourceId: string; sourceHandleId?: string | null }
  | { type: 'connectOver'; targetId: string; targetHandleId?: string | null }
  | { type: 'connectEnd' }
  | {
      type: 'moveSpace';
      spaceId: string;
      movement?: unknown;
      effect?: FociSpaceMoveEffect;
    };

interface FociNode extends FociNodeRegistration {
  policy: FociNodePolicy;
}

interface ClickOptions extends FociTraversalOptions {
  detail?: number;
  additive?: boolean;
  range?: boolean;
  /**
   * Semantic DOM path, ordered leaf -> root, captured from the live event path.
   *
   * Pointer ownership must be resolved from the event path that actually
   * received the click. Registry parent links are useful for compiler facts,
   * but they can be stale or ambiguous when repeated anonymous descendants
   * temporarily share an id.
   */
  pointerPath?: readonly string[];
}

interface KeyOptions {
  shift?: boolean;
  meta?: boolean;
  ctrl?: boolean;
  alt?: boolean;
  mode?: FociMode;
  aspects?: readonly FociPresetAspect[];
  focusId?: string | null;
}

export interface FociCancelOptions {
  trigger?: FociCancelTrigger;
  targetId?: string | null;
  focusId?: string | null;
  scopeId?: string | null;
  restoreSource?: boolean;
  mode?: FociMode;
  aspects?: readonly FociPresetAspect[];
  rootId?: string | null;
  inspect?: boolean;
}

export interface FociCommitOptions {
  trigger?: FociCommitTrigger;
  advance?: 'none' | 'up' | 'down';
  restoreSource?: boolean;
}

export interface FociSelectOptions {
  additive?: boolean;
  range?: boolean;
  /**
   * Close an active input session when the selected target is being restored as
   * the durable source. This is distinct from normal selection while an input
   * is open, where the source should remain selected but visually quiet.
   */
  restoreSource?: boolean;
}

interface FociMovementResult {
  type: 'resolved' | 'delegated';
  targetId?: string;
  ownerId?: string;
  scopeId: string;
  axis: FociMoveAxis;
}

interface FociNodeVisualResolution {
  adornments: readonly FociVisualAdornment[];
  suppressed: readonly FociProjectionAdornment[];
}

interface FociProjectionVisualResolution {
  nodeVisuals: ReadonlyMap<string, FociNodeVisualResolution>;
  decals: readonly FociProjectionDecal[];
  suppressedDecals: readonly FociProjectionDecal[];
  primary: FociProjectionVisualPrimary | null;
}

export class FociStore {
  private nodes = new Map<string, FociNode>();
  private children = new Map<string | null, string[]>();
  private program: CompiledFociProgram = compileFociProgram([]);
  private pathCache = new Map<string, readonly string[]>();
  private scopeIdCache = new Map<string, string>();
  private focusPath: readonly string[] = [];
  private selections = new Map<string, FociSelectionSnapshot>();
  private selectionActivatedAt = new Map<string, number>();
  private activeScopeId: string | null = null;
  private hoveredId: string | null = null;
  private input: FociInputSession | null = null;
  private overlay: FociOverlaySession | null = null;
  private transfer: FociTransferSnapshot | null = null;
  private coordinateRevisions = new Map<string, number>();
  private logEntries: string[] = [];
  private snapshotVersionValue = 0;
  private snapshotVersionKey = '';

  register(registration: FociNodeRegistration): void {
    this.addRegistration(registration);
    this.refreshCompiledProgram();
  }

  load(registrations: readonly FociNodeRegistration[]): this {
    this.clearAll();
    for (const registration of registrations) {
      this.addRegistration(registration);
    }
    this.refreshCompiledProgram();
    return this;
  }

  private addRegistration(registration: FociNodeRegistration): void {
    const existing = this.nodes.get(registration.id);
    const node: FociNode = {
      ...registration,
      policy: compileFociPolicy(registration),
    };
    this.nodes.set(node.id, node);

    if (!existing || existing.parentId !== node.parentId) {
      if (existing) this.removeChild(existing.parentId, node.id);
      const ids = this.children.get(node.parentId)?.slice() ?? [];
      if (!ids.includes(node.id)) ids.push(node.id);
      this.children.set(node.parentId, ids);
    }
  }

  node(id: string): FociNodeRegistration | null {
    return this.nodes.get(id) ?? null;
  }

  traversalSet(options: FociTraversalOptions = {}): FociTraversalSet {
    const mode = options.mode ?? 'use';
    const rootId = options.rootId ?? null;
    const inheritedAspects = new Set(options.aspects ?? []);
    const stops: FociTraversalStop[] = [];
    const baseAxes = traversalAxesFor(mode, options.inspect);
    const axes =
      this.transfer && !baseAxes.includes('receivers')
        ? [...baseAxes, 'receivers' as const]
        : baseAxes;

    const visit = (id: string): void => {
      const node = this.nodes.get(id);
      if (!node) return;
      if (node.policy.traversal === 'skip') return;

      const aspects = this.effectiveAspectsFor(node, mode, inheritedAspects);
      const stop = this.traversalStopFor(node, mode, axes, aspects);
      const boundary =
        node.policy.traversal === 'boundary' ||
        (stop !== null && this.isAutoBoundary(node, mode, aspects));

      if (stop) stops.push(stop);

      if (
        boundary ||
        (stop?.reason === 'sheet-cell' && (mode === 'use' || mode === 'change'))
      ) {
        return;
      }

      for (const childId of this.children.get(id) ?? []) {
        visit(childId);
      }
    };

    if (rootId === null) {
      for (const id of this.children.get(null) ?? []) visit(id);
    } else {
      for (const id of this.children.get(rootId) ?? []) visit(id);
    }

    const aspects = [...inheritedAspects];
    return {
      mode,
      axes,
      aspects,
      rootId,
      ids: stops.map((stop) => stop.id),
      stops,
    };
  }

  projection(options: FociTraversalOptions = {}): FociProjection {
    const mode = options.mode ?? 'use';
    const traversal = this.traversalSet(options);
    const stopById = new Map(
      traversal.stops.map((stop) => [stop.id, stop] as const),
    );
    const activeSelection = this.activeSelection();
    const selectedIds = new Set(
      [...this.selections.values()].flatMap((selection) => selection.ids),
    );
    const rangeIds = new Set(
      activeSelection && activeSelection.ids.length > 1
        ? activeSelection.ids
        : [],
    );
    const layerRolesById = this.projectedLayerRoles();
    const rawNodes: FociProjectionNode[] = [];

    for (const id of this.treeIds()) {
      const node = this.nodes.get(id)!;
      const stop = stopById.get(id);
      const layerRoles = layerRolesById.get(id) ?? [];
      const adornments = this.projectionAdornmentsFor(node, {
        mode,
        stop,
        layerRoles,
        rangeIds,
      });
      const programmaticFocusable = this.isPointerFocusableTarget(node);
      const browserFocusable = Boolean(stop);
      const focused = this.focusedId === id;
      const projected: FociProjectionNode = {
        id,
        surface: node.surface,
        target: node.target,
        focusKey: node.focusKey,
        scopeId: this.scopeIdFor(node),
        traversalStop: Boolean(stop),
        traversalReason: stop?.reason,
        selectable: (node.policy.selection ?? 'single') !== 'none',
        editable: this.isEditableStop(node),
        receiver: stop?.reason === 'receiver',
        browserFocusable,
        programmaticFocusable,
        tabIndex: browserFocusable
          ? 0
          : focused && programmaticFocusable
            ? -1
            : null,
        focusPath: this.focusPath.includes(id),
        focused,
        hovered: this.hoveredId === id,
        selected: selectedIds.has(id),
        layerRoles,
        adornments,
        visualAdornments: adornments,
        surfaceAdornments: adornments,
        decalAdornments: [],
        adornmentPresentation: {},
        suppressedAdornments: [],
        decalShape: node.policy.decalShape,
      };
      rawNodes.push(projected);
    }

    const rawDecals = this.projectionDecals(traversal, mode);
    const visualResolution = this.resolveProjectionVisuals({
      mode,
      nodes: rawNodes,
      decals: rawDecals,
    });
    const nodes = rawNodes.map((node) => {
      const visual = visualResolution.nodeVisuals.get(node.id);
      const visualAdornments = visual?.adornments ?? node.adornments;
      const adornmentResolution = this.resolveAdornmentPresentation(
        node.id,
        visualAdornments,
      );
      return {
        ...node,
        visualAdornments,
        surfaceAdornments: adornmentResolution.surfaceAdornments,
        decalAdornments: adornmentResolution.decalAdornments,
        adornmentPresentation: adornmentResolution.presentation,
        suppressedAdornments: visual?.suppressed ?? [],
      };
    });
    const nodeMap = new Map(nodes.map((node) => [node.id, node] as const));
    const presentationSuppressedDecals: FociProjectionDecal[] = [];
    const visualDecals =
      mode === 'debug'
        ? visualResolution.decals
        : visualResolution.decals.filter((decal) => {
            if (this.shouldRenderDecal(decal)) return true;
            presentationSuppressedDecals.push(decal);
            return false;
          });

    return {
      mode,
      traversal,
      nodes,
      nodeMap,
      decals: rawDecals,
      visualDecals,
      suppressedDecals: [
        ...visualResolution.suppressedDecals,
        ...presentationSuppressedDecals,
      ],
      visualPrimary: visualResolution.primary,
    };
  }

  firstTraversalId(options: FociTraversalOptions = {}): string | null {
    return this.traversalSet(options).ids[0] ?? null;
  }

  nextTraversalId(
    id: string | null,
    options: FociTraversalOptions = {},
  ): string | null {
    return this.stepTraversalId(id, 1, options);
  }

  prevTraversalId(
    id: string | null,
    options: FociTraversalOptions = {},
  ): string | null {
    return this.stepTraversalId(id, -1, options);
  }

  dispatch(event: FociSemanticEvent): FociDispatchResult {
    switch (event.type) {
      case 'click':
        return this.click(event.targetId, event);
      case 'hover':
        return this.hover(event.targetId);
      case 'key':
        return this.key(event.key, event);
      case 'move':
        return this.move(event.direction, event);
      case 'activate':
        return this.activate(event);
      case 'edit':
        return this.requestEdit(event);
      case 'commitInput':
        return this.commitInput(event);
      case 'escape':
        return this.escape(event);
      case 'cancel':
        return this.cancel(event);
      case 'copy':
        return this.copy();
      case 'paste':
        return this.paste();
      case 'dragStart':
        return this.dragStart(event.targetId);
      case 'dragOver':
        return this.dragOver(event.targetId);
      case 'drop':
        return this.drop();
      case 'connectStart':
        return this.connectStart(event.sourceId, event.sourceHandleId);
      case 'connectOver':
        return this.connectOver(event.targetId, event.targetHandleId);
      case 'connectEnd':
        return this.connectEnd();
      case 'moveSpace':
        return this.moveSpace(event.spaceId, event.movement, event.effect);
    }
  }

  click(rawTargetId: string, options: ClickOptions = {}): FociDispatchResult {
    const targetId = this.resolvePointerTarget(rawTargetId, options);
    if (!targetId) {
      this.record(`click:${rawTargetId}:ignored`);
      return { handled: false, ownerId: null, reason: 'preview-only' };
    }

    const target = this.nodes.get(targetId);
    if (!target) {
      return { handled: false, ownerId: null, reason: 'unknown-target' };
    }

    if (this.input && !this.isSameInputSource(targetId)) {
      this.closeInput(false);
    }

    if (!this.isPointerFocusableTarget(target)) {
      this.closePreview();
      const cancelled = this.cancel({
        trigger: 'click-away',
        targetId: target.id,
        focusId: this.focusedId,
      });
      if (cancelled.handled) return cancelled;
      this.record(`click:${target.id}:not-selectable`);
      return { handled: false, ownerId: target.id, reason: 'not-selectable' };
    }

    if (target.target === 'action') {
      const sourceId = this.activeSelection()?.headId ?? target.parentId;
      this.openMenu(sourceId, targetId);
      return { handled: true, ownerId: targetId, reason: 'action-menu' };
    }

    if (target.policy.pointer === 'content-interactive') {
      this.input = this.createInputSession({
        kind: 'control',
        targetId: target.id,
        keyboardOwnerId: target.id,
        sourceId: this.activeSelection()?.headId ?? target.parentId,
        visualSuppression: 'source-anchor',
        policyNode: target,
      });
      this.focusTo(target.id);
      this.record(`control:${target.id}`);
      return { handled: true, ownerId: target.id, reason: 'control-focus' };
    }

    const editPolicy = target.policy.edit ?? 'none';
    const shouldPromoteToEdit = editPolicy !== 'none' && options.detail === 2;

    if (shouldPromoteToEdit) {
      const intent = this.openEditor(target.id);
      return {
        handled: true,
        ownerId: target.id,
        reason: 'open-editor',
        intent,
      };
    }

    this.closePreview();
    this.select(target.id, options);
    return { handled: true, ownerId: target.id, reason: 'select' };
  }

  hover(rawTargetId: string | null): FociDispatchResult {
    if (rawTargetId === null) {
      this.hoveredId = null;
      this.closePreview();
      this.record('hover:clear');
      return { handled: true, ownerId: null, reason: 'hover-clear' };
    }

    const targetId = this.resolvePointerTarget(rawTargetId);
    if (!targetId) {
      this.record(`hover:${rawTargetId}:ignored`);
      return { handled: false, ownerId: null, reason: 'preview-only' };
    }

    const target = this.nodes.get(targetId);
    if (!target) {
      return { handled: false, ownerId: null, reason: 'unknown-target' };
    }

    this.hoveredId = target.id;
    if (
      target.policy.lift === 'hover-preview' &&
      this.activeSelection()?.headId === target.id &&
      !this.input
    ) {
      this.overlay = this.createOverlay('preview', target.id, false);
      this.record(`preview:${target.id}`);
      return { handled: true, ownerId: target.id, reason: 'preview' };
    }

    this.record(`hover:${target.id}`);
    return { handled: true, ownerId: target.id, reason: 'hover' };
  }

  activate(options: KeyOptions = {}): FociDispatchResult {
    if (this.input) {
      const ownerId = this.input.id;
      if (this.input.kind === 'editor') {
        return this.commitEditor(ownerId, options);
      }
      if (this.input.kind === 'drag') {
        const targetId = this.focusedId;
        return {
          handled: Boolean(targetId),
          ownerId: targetId,
          reason: targetId ? 'drop-on-focus' : 'no-drop-target',
          intent: {
            type: 'drop-on-focus',
            sourceId: this.input.sourceId,
            targetId,
          },
        };
      }
      this.record(`activate:input:${ownerId}`);
      return { handled: true, ownerId, reason: 'input-owned-activation' };
    }

    const headId = this.keyboardHeadId();
    if (!headId) {
      return { handled: false, ownerId: null, reason: 'no-focus' };
    }

    const head = this.nodes.get(headId);
    if (!head) {
      return { handled: false, ownerId: null, reason: 'unknown-focus' };
    }

    if (head.target === 'action') {
      const sourceId =
        this.activeSelection()?.headId ?? head.parentId ?? head.id;
      this.openMenu(sourceId, head.id);
      return {
        handled: true,
        ownerId: head.id,
        reason: 'action-menu',
        intent: { type: 'open-menu', sourceId, targetId: head.id },
      };
    }

    if (head.policy.pointer === 'content-interactive') {
      const sourceId = this.activeSelection()?.headId ?? head.parentId ?? null;
      this.input = this.createInputSession({
        kind: 'control',
        targetId: head.id,
        keyboardOwnerId: head.id,
        sourceId,
        visualSuppression: 'source-anchor',
        policyNode: head,
      });
      this.focusTo(head.id);
      this.record(`control:${head.id}`);
      return {
        handled: true,
        ownerId: head.id,
        reason: 'control-focus',
        intent: { type: 'focus-control', targetId: head.id, sourceId },
      };
    }

    const editResult = this.requestEdit(options);
    if (editResult.handled) return editResult;

    const editableDescendantId = this.primaryEditableDescendantIdFor(head);
    if (editableDescendantId) {
      const intent = this.openEditor(editableDescendantId);
      return {
        handled: true,
        ownerId: editableDescendantId,
        reason: 'open-editor',
        intent,
      };
    }

    if (this.isActivatableBoundary(head)) {
      this.record(`activate:drill:${head.id}`);
      return {
        handled: true,
        ownerId: head.id,
        reason: 'drill-in',
        intent: { type: 'drill-in', targetId: head.id },
      };
    }

    this.record(`activate:${head.id}:ignored`);
    return { handled: false, ownerId: head.id, reason: 'not-activatable' };
  }

  requestEdit(
    options: KeyOptions & { seed?: string } = {},
  ): FociDispatchResult {
    const headId = this.keyboardHeadId();
    if (!headId) {
      return { handled: false, ownerId: null, reason: 'no-focus' };
    }

    const head = this.nodes.get(headId);
    if (!head) {
      return { handled: false, ownerId: null, reason: 'unknown-focus' };
    }

    if ((head.policy.edit ?? 'none') === 'none') {
      return { handled: false, ownerId: head.id, reason: 'not-editable' };
    }

    const intent = this.openEditor(head.id, options.seed);
    return {
      handled: true,
      ownerId: head.id,
      reason: 'open-editor',
      intent,
    };
  }

  move(
    direction: FociMoveDirection,
    options: KeyOptions = {},
  ): FociDispatchResult {
    if (this.input) {
      const ownerId = this.input.id;
      this.record(`move:${direction}:input:${ownerId}`);
      return { handled: true, ownerId, reason: 'input-owned-key' };
    }

    const headId = this.keyboardHeadId();
    if (!headId) {
      return { handled: false, ownerId: null, reason: 'no-focus' };
    }

    const head = this.nodes.get(headId);
    if (!head) {
      return { handled: false, ownerId: null, reason: 'unknown-focus' };
    }

    const movement = this.moveFrom(head.id, direction, options);
    if (movement?.type === 'delegated') {
      return {
        handled: true,
        ownerId: movement.ownerId ?? head.id,
        reason: 'move-request',
        intent: {
          type: 'resolve-move',
          ownerId: movement.ownerId ?? head.id,
          sourceId: head.id,
          direction,
          axis: movement.axis,
          range: Boolean(options.shift),
          scopeId: movement.scopeId,
        },
      };
    }

    return {
      handled: movement !== null,
      ownerId: head.id,
      reason: movement ? 'move-selection-head' : 'edge',
      reveal: movement?.targetId
        ? {
            targetId: movement.targetId,
            block: 'nearest',
            inline: 'nearest',
            reason: 'keyboard',
          }
        : undefined,
      intent: movement?.targetId
        ? {
            type: 'move-selection',
            sourceId: head.id,
            targetId: movement.targetId,
            direction,
            axis: movement.axis,
            range: Boolean(options.shift),
            scopeId: movement.scopeId,
          }
        : undefined,
    };
  }

  key(key: string, options: KeyOptions = {}): FociDispatchResult {
    if (this.input) {
      const ownerId = this.input.id;
      if (this.input.kind === 'drag' && key === 'Tab') {
        const moved = this.stepTraversal(options.shift ? -1 : 1, {
          mode: options.mode ?? 'use',
          aspects: options.aspects,
        });
        return {
          handled: moved,
          ownerId: this.focusedId,
          reason: moved ? 'traverse-transfer' : 'traversal-empty',
        };
      }

      if (key === 'Escape') {
        const sourceId = this.input.sourceId;
        this.closeInput(true);
        return {
          handled: true,
          ownerId,
          reason: sourceId ? 'close-input-restore-source' : 'close-input',
        };
      }

      if (key === 'Enter' && this.input.kind === 'editor') {
        return this.activate(options);
      }

      this.record(`key:${key}:input:${ownerId}`);
      return { handled: true, ownerId, reason: 'input-owned-key' };
    }

    if (key === 'Escape' && this.overlay?.activityRole === 'preview') {
      const ownerId = this.overlay.sourceId;
      this.closePreview();
      return { handled: true, ownerId, reason: 'close-preview' };
    }

    if (this.transfer && key === 'Escape') {
      this.transfer = null;
      this.record('transfer:cancel');
      return { handled: true, ownerId: null, reason: 'cancel-transfer' };
    }

    if (key === 'Tab') {
      const moved = this.stepTraversal(options.shift ? -1 : 1, {
        mode: options.mode ?? 'use',
        aspects: options.aspects,
      });
      return {
        handled: moved,
        ownerId: this.focusedId,
        reason: moved ? 'traverse' : 'traversal-empty',
      };
    }

    if (key === 'Escape') {
      return this.escape(options);
    }

    const headId = this.activeSelection()?.headId ?? this.focusedId;
    if (!headId) {
      return { handled: false, ownerId: null, reason: 'no-focus' };
    }

    const head = this.nodes.get(headId);
    if (!head) {
      return { handled: false, ownerId: null, reason: 'unknown-focus' };
    }

    if (key === 'Enter') {
      return this.activate(options);
    }

    if (key === 'F2') {
      return this.requestEdit(options);
    }

    if (isPrintableKey(key)) {
      return this.requestEdit({ ...options, seed: key });
    }

    if (isArrowKey(key)) {
      return this.move(directionFromArrowKey(key), options);
    }

    return { handled: false, ownerId: head.id, reason: 'unhandled-key' };
  }

  escape(options: KeyOptions = {}): FociDispatchResult {
    return this.cancel({
      trigger: 'escape',
      focusId: options.focusId ?? this.focusedId,
    });
  }

  commitInput(options: FociCommitOptions = {}): FociDispatchResult {
    if (!this.input) {
      return { handled: false, ownerId: this.focusedId, reason: 'no-input' };
    }

    const session = this.input;
    const sourceId = session.sourceId;
    const trigger = options.trigger ?? 'explicit';
    const advance = options.advance ?? 'none';
    this.closeInput(
      options.restoreSource ?? session.cancelPolicy.restoreSource,
    );
    if (sourceId && advance !== 'none') {
      this.advanceFrom(sourceId, advance);
    }
    return {
      handled: true,
      ownerId: session.targetId,
      reason: 'commit-input',
      intent: {
        type: 'commit-input',
        sourceId,
        targetId: session.targetId,
        trigger,
        advance,
      },
    };
  }

  cancel(options: FociCancelOptions = {}): FociDispatchResult {
    const trigger = options.trigger ?? 'programmatic';
    if (this.input) {
      const session = this.input;
      const ownerId = session.id;
      const sourceId = session.sourceId;
      this.closeInput(
        options.restoreSource ?? session.cancelPolicy.restoreSource,
      );
      return {
        handled: true,
        ownerId,
        reason: isOutsideClickTrigger(trigger)
          ? 'click-away-close-input'
          : sourceId
            ? 'close-input-restore-source'
            : 'close-input',
      };
    }

    if (this.overlay?.activityRole === 'preview') {
      const ownerId = this.overlay.sourceId;
      this.closePreview();
      return { handled: true, ownerId, reason: 'close-preview' };
    }

    if (this.transfer) {
      this.transfer = null;
      this.record('transfer:cancel');
      return { handled: true, ownerId: null, reason: 'cancel-transfer' };
    }

    const focusId = this.resolveFocusId(options.focusId ?? this.focusedId);
    const activeScopeId = this.activeScopeId;
    const scopeId = this.selectionScopeForCancel(options, focusId);
    if (scopeId) {
      const selection = this.selections.get(scopeId);
      const parentScopeId = selection
        ? this.parentSelectionScopeFor(selection)
        : null;
      const intentType =
        (trigger === 'escape' && scopeId === activeScopeId) || parentScopeId
          ? 'go-up-level'
          : 'dismiss-selection';
      return this.clearSelectionScope(scopeId, {
        focusId,
        reason: isOutsideClickTrigger(trigger)
          ? 'click-away-cancel'
          : intentType === 'go-up-level'
            ? 'escape-up-level'
            : 'dismiss-focused-selection',
        intentType,
      });
    }

    this.record(
      isOutsideClickTrigger(trigger)
        ? 'click-away:nothing'
        : focusId
          ? `escape:${focusId}:nothing`
          : 'escape:nothing',
    );
    return {
      handled: false,
      ownerId: focusId,
      reason: 'nothing-to-dismiss',
    };
  }

  copy(): FociDispatchResult {
    const selection = this.activeSelection();
    if (!selection) {
      return { handled: false, ownerId: null, reason: 'no-selection' };
    }
    this.transfer = { kind: 'copy', origin: cloneSelection(selection) };
    this.record(`copy:${selection.scopeId}:${selection.ids.join(',')}`);
    return { handled: true, ownerId: selection.headId, reason: 'copy' };
  }

  paste(): FociDispatchResult {
    if (!this.transfer || this.transfer.kind !== 'copy') {
      return { handled: false, ownerId: null, reason: 'no-copy-origin' };
    }
    const targetId = this.destinationHeadId();
    if (!targetId) {
      return { handled: false, ownerId: null, reason: 'no-destination' };
    }
    const destination = this.destinationFor(targetId, 'copy');
    if (!destination) {
      return { handled: false, ownerId: targetId, reason: 'rejected' };
    }
    this.transfer = { ...this.transfer, destination };
    this.record(`paste:${this.transfer.origin.scopeId}->${targetId}`);
    this.transfer = null;
    return { handled: true, ownerId: targetId, reason: 'paste' };
  }

  dragStart(rawTargetId: string): FociDispatchResult {
    const targetId = this.resolvePointerTarget(rawTargetId);
    if (!targetId) {
      return { handled: false, ownerId: null, reason: 'preview-only' };
    }
    const selected = this.selectionContaining(targetId);
    if (!selected) this.select(targetId);
    const origin = this.selectionContaining(targetId) ?? this.activeSelection();
    if (!origin) {
      return { handled: false, ownerId: targetId, reason: 'no-origin' };
    }

    this.transfer = {
      kind: 'drag',
      origin: cloneSelection(origin),
      pointerCaptured: true,
      movedPastThreshold: false,
    };
    this.input = this.createInputSession({
      kind: 'drag',
      targetId: `${targetId}::drag`,
      keyboardOwnerId: `${targetId}::drag`,
      sourceId: targetId,
      visualSuppression: 'transfer-lock',
      policyNode: this.nodes.get(targetId),
      commitModel: 'command',
      commitTriggers: ['release'],
    });
    this.record(`drag:start:${targetId}`);
    return { handled: true, ownerId: targetId, reason: 'drag-start' };
  }

  dragOver(rawTargetId: string): FociDispatchResult {
    if (!this.transfer || this.transfer.kind !== 'drag') {
      return { handled: false, ownerId: null, reason: 'no-drag-origin' };
    }
    const targetId = this.resolvePointerTarget(rawTargetId);
    if (!targetId) {
      return { handled: false, ownerId: null, reason: 'preview-only' };
    }
    const destination = this.destinationFor(targetId, 'move');
    if (!destination) {
      return { handled: false, ownerId: targetId, reason: 'rejected' };
    }
    this.transfer = {
      ...this.transfer,
      destination,
      movedPastThreshold: true,
    };
    this.record(`drag:over:${targetId}`);
    return { handled: true, ownerId: targetId, reason: 'drag-over' };
  }

  drop(): FociDispatchResult {
    if (!this.transfer || this.transfer.kind !== 'drag') {
      return { handled: false, ownerId: null, reason: 'no-drag' };
    }
    const destinationId = this.transfer.destination?.targetId ?? null;
    this.record(`drag:drop:${destinationId ?? 'none'}`);
    this.transfer = null;
    this.input = null;
    return {
      handled: destinationId !== null,
      ownerId: destinationId,
      reason: 'drop',
    };
  }

  connectStart(
    rawSourceId: string,
    sourceHandleId?: string | null,
  ): FociDispatchResult {
    const sourceId = this.resolvePointerTarget(rawSourceId);
    if (!sourceId) {
      return { handled: false, ownerId: null, reason: 'preview-only' };
    }
    const selected = this.selectionContaining(sourceId);
    if (!selected) this.select(sourceId);
    const origin = this.selectionContaining(sourceId) ?? this.activeSelection();
    if (!origin) {
      return { handled: false, ownerId: sourceId, reason: 'no-origin' };
    }

    this.transfer = {
      kind: 'connect',
      origin: cloneSelection(origin),
      sourceHandleId: sourceHandleId ?? null,
      pointerCaptured: true,
      movedPastThreshold: false,
    };
    this.input = this.createInputSession({
      kind: 'connect',
      targetId: `${sourceId}::connect`,
      keyboardOwnerId: `${sourceId}::connect`,
      sourceId,
      visualSuppression: 'transfer-lock',
      policyNode: this.nodes.get(sourceId),
      commitModel: 'command',
      commitTriggers: ['release'],
    });
    this.record(`connect:start:${sourceId}`);
    return { handled: true, ownerId: sourceId, reason: 'connect-start' };
  }

  connectOver(
    rawTargetId: string,
    targetHandleId?: string | null,
  ): FociDispatchResult {
    if (!this.transfer || this.transfer.kind !== 'connect') {
      return { handled: false, ownerId: null, reason: 'no-connect-origin' };
    }
    const targetId = this.resolvePointerTarget(rawTargetId);
    if (!targetId) {
      return { handled: false, ownerId: null, reason: 'preview-only' };
    }
    const destination = this.destinationFor(targetId, 'connect');
    if (!destination) {
      return { handled: false, ownerId: targetId, reason: 'rejected' };
    }
    this.transfer = {
      ...this.transfer,
      destination,
      targetHandleId: targetHandleId ?? null,
      movedPastThreshold: true,
    };
    this.record(`connect:over:${targetId}`);
    return { handled: true, ownerId: targetId, reason: 'connect-over' };
  }

  connectEnd(): FociDispatchResult {
    if (!this.transfer || this.transfer.kind !== 'connect') {
      return { handled: false, ownerId: null, reason: 'no-connect' };
    }
    const destinationId = this.transfer.destination?.targetId ?? null;
    this.record(`connect:end:${destinationId ?? 'none'}`);
    this.transfer = null;
    this.input = null;
    return {
      handled: destinationId !== null,
      ownerId: destinationId,
      reason: 'connect-end',
    };
  }

  moveSpace(
    spaceId: string,
    _movement?: unknown,
    effect?: FociSpaceMoveEffect,
  ): FociDispatchResult {
    const space = this.nodes.get(spaceId);
    if (!space) {
      return { handled: false, ownerId: null, reason: 'unknown-space' };
    }

    const revision = (this.coordinateRevisions.get(spaceId) ?? 0) + 1;
    this.coordinateRevisions.set(spaceId, revision);

    const moveEffect =
      effect ?? space.policy.coordinateSpace?.moveEffect ?? 'preserve-input';
    const sourceId =
      this.input?.sourceId ?? this.overlay?.sourceId ?? this.focusedId;
    const affected =
      sourceId !== null &&
      sourceId !== undefined &&
      (sourceId === spaceId || this.pathTo(sourceId).includes(spaceId));

    if (!affected) {
      this.record(`space:${spaceId}:move:unaffected`);
      return {
        handled: true,
        ownerId: spaceId,
        reason: 'space-move-unaffected',
      };
    }

    switch (moveEffect) {
      case 'dismiss-input':
        this.closeInput(true);
        this.closePreview();
        this.record(`space:${spaceId}:move:dismiss-input`);
        return {
          handled: true,
          ownerId: spaceId,
          reason: 'space-move-dismiss-input',
        };
      case 'clear-selection':
        this.closeInput(true);
        this.closePreview();
        this.clearActiveScope();
        this.record(`space:${spaceId}:move:clear-selection`);
        return {
          handled: true,
          ownerId: spaceId,
          reason: 'space-move-clear-selection',
        };
      case 'reanchor-overlay':
        if (this.overlay) {
          this.overlay = {
            ...this.overlay,
            coordinateSpaceId: spaceId,
            coordinateRevision: revision,
          };
        }
        this.record(`space:${spaceId}:move:reanchor-overlay`);
        return {
          handled: true,
          ownerId: spaceId,
          reason: 'space-move-reanchor-overlay',
        };
      case 'preserve-input':
      default:
        this.record(`space:${spaceId}:move:preserve-input`);
        return {
          handled: true,
          ownerId: spaceId,
          reason: 'space-move-preserve-input',
        };
    }
  }

  openTools(sourceId: string, toolsId = `${sourceId}::tools`): void {
    this.overlay = this.createOverlay('tools', sourceId, true, toolsId);
    this.input = this.createInputSession({
      kind: 'tools',
      targetId: toolsId,
      keyboardOwnerId: toolsId,
      sourceId,
      liftedTargetId: toolsId,
      visualSuppression: 'source-anchor',
      policyNode: this.nodes.get(sourceId),
      commitModel: 'command',
      commitTriggers: ['explicit'],
    });
    this.record(`tools:${sourceId}`);
  }

  snapshot(): FociStoreSnapshot {
    return {
      focusPath: [...this.focusPath],
      focusedId: this.focusedId,
      hoveredId: this.hoveredId,
      activeScopeId: this.activeScopeId,
      selections: Object.fromEntries(
        [...this.selections].map(([scopeId, selection]) => [
          scopeId,
          cloneSelection(selection),
        ]),
      ),
      layers: this.layers(),
      input: this.input
        ? {
            ...this.input,
            commitPolicy: {
              ...this.input.commitPolicy,
              triggers: [...this.input.commitPolicy.triggers],
            },
            cancelPolicy: {
              ...this.input.cancelPolicy,
              triggers: [...this.input.cancelPolicy.triggers],
            },
          }
        : null,
      overlay: this.overlay ? { ...this.overlay } : null,
      transfer: this.transfer
        ? {
            ...this.transfer,
            origin: cloneSelection(this.transfer.origin),
            destination: this.transfer.destination
              ? { ...this.transfer.destination }
              : undefined,
          }
        : null,
      coordinateRevisions: Object.fromEntries(this.coordinateRevisions),
      tree: this.treeSnapshot(),
      log: [...this.logEntries],
    };
  }

  get focusedId(): string | null {
    return this.focusPath[this.focusPath.length - 1] ?? null;
  }

  get snapshotVersion(): number {
    const key = this.snapshotStateKey();
    if (key !== this.snapshotVersionKey) {
      this.snapshotVersionKey = key;
      this.snapshotVersionValue += 1;
    }
    return this.snapshotVersionValue;
  }

  private snapshotStateKey(): string {
    return JSON.stringify({
      focusPath: this.focusPath,
      activeScopeId: this.activeScopeId,
      hoveredId: this.hoveredId,
      selections: [...this.selections]
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([scopeId, selection]) => [
          scopeId,
          selection.headId,
          selection.anchorId,
          selection.scopeKind,
          selection.ids,
          selection.range ?? null,
        ]),
      input: this.input
        ? {
            kind: this.input.kind,
            id: this.input.id,
            targetId: this.input.targetId,
            sourceId: this.input.sourceId,
            liftedTargetId: this.input.liftedTargetId,
            keyboardOwnerId: this.input.keyboardOwnerId,
            visualSuppression: this.input.visualSuppression,
            commitPolicy: this.input.commitPolicy,
            cancelPolicy: this.input.cancelPolicy,
          }
        : null,
      overlay: this.overlay,
      transfer: this.transfer
        ? {
            ...this.transfer,
            origin: [
              this.transfer.origin.scopeId,
              this.transfer.origin.headId,
              this.transfer.origin.anchorId,
              this.transfer.origin.scopeKind,
              this.transfer.origin.ids,
              this.transfer.origin.range ?? null,
            ],
          }
        : null,
      coordinateRevisions: [...this.coordinateRevisions].sort(
        ([left], [right]) => left.localeCompare(right),
      ),
    });
  }

  private clearAll(): void {
    this.nodes.clear();
    this.children.clear();
    this.program = compileFociProgram([]);
    this.clearTopologyCaches();
    this.focusPath = [];
    this.selections.clear();
    this.selectionActivatedAt.clear();
    this.activeScopeId = null;
    this.hoveredId = null;
    this.input = null;
    this.overlay = null;
    this.transfer = null;
    this.coordinateRevisions.clear();
    this.logEntries = [];
  }

  private refreshCompiledProgram(): void {
    this.program = compileFociProgram([...this.nodes.values()]);
    for (const compiled of this.program.nodes) {
      const node = this.nodes.get(compiled.id);
      if (node) node.policy = compiled.policy;
    }
    this.clearTopologyCaches();
  }

  private clearTopologyCaches(): void {
    this.pathCache.clear();
    this.scopeIdCache.clear();
  }

  private compiledNodeFor(node: FociNode | string): CompiledFociNode | null {
    const id = typeof node === 'string' ? node : node.id;
    return this.program.nodeMap.get(id) ?? null;
  }

  private removeChild(parentId: string | null, childId: string): void {
    const ids = this.children.get(parentId);
    if (!ids) return;
    const next = ids.filter((id) => id !== childId);
    if (next.length > 0) this.children.set(parentId, next);
    else this.children.delete(parentId);
  }

  private resolvePointerTarget(
    rawTargetId: string,
    options: FociTraversalOptions = {},
  ): string | null {
    const leafToRoot = this.pointerPathToRoot(rawTargetId, options);
    if (leafToRoot.length === 0) return null;
    for (const id of leafToRoot) {
      const node = this.nodes.get(id);
      if (node?.policy.pointer === 'preview-only') return null;
    }
    const leafId = leafToRoot[0] ?? rawTargetId;
    const leaf = this.nodes.get(leafId) ?? this.nodes.get(rawTargetId);
    if (!leaf) return null;

    const atomicAncestor = this.atomicSelectionAncestorFor(
      rawTargetId,
      options,
      leafToRoot,
    );
    if (atomicAncestor) {
      const leafCanOwnInteraction =
        leaf.policy.pointer === 'content-interactive' ||
        leaf.target === 'action' ||
        leaf.policy.keyboard === 'editor';
      const atomicAlreadySelected =
        this.selectionContaining(atomicAncestor)?.ids.includes(
          atomicAncestor,
        ) ?? false;
      const activeInputSource = this.input?.sourceId === atomicAncestor;
      if (
        leafCanOwnInteraction &&
        (atomicAlreadySelected || activeInputSource)
      ) {
        return leaf.id;
      }
      return atomicAncestor;
    }

    if (
      leaf.policy.pointer === 'content-interactive' ||
      leaf.target === 'action' ||
      leaf.policy.keyboard === 'editor'
    ) {
      return leaf.id;
    }
    if ((leaf.policy.selection ?? 'single') !== 'none') {
      return leaf.id;
    }
    for (const id of leafToRoot) {
      const node = this.nodes.get(id);
      if (!node) continue;
      if (
        node.policy.pointer === 'surface-owned' ||
        node.policy.pointer === 'cell-owned'
      ) {
        return node.id;
      }
    }
    const traversalIds = new Set(this.traversalSet(options).ids);
    for (const id of leafToRoot) {
      if (traversalIds.has(id)) return id;
    }
    if (leaf.target === 'structure') return null;
    return leaf.id;
  }

  private pointerPathToRoot(
    rawTargetId: string,
    options: FociTraversalOptions,
  ): string[] {
    const optionPath =
      'pointerPath' in options
        ? (options as ClickOptions).pointerPath
        : undefined;
    if (optionPath && optionPath.length > 0) {
      return uniqueKnownPath(optionPath, this.nodes);
    }

    const path = this.pathTo(rawTargetId);
    return [...path].reverse();
  }

  private atomicSelectionAncestorFor(
    rawTargetId: string,
    options: FociTraversalOptions,
    leafToRoot = this.pointerPathToRoot(rawTargetId, options),
  ): string | null {
    const mode = options.mode ?? 'use';
    if (mode !== 'use' && mode !== 'change') return null;

    if (leafToRoot.length < 2) return null;

    const explicitAspects = new Set(options.aspects ?? []);
    const axes = traversalAxesFor(mode, options.inspect);
    for (const id of leafToRoot.slice(1)) {
      const node = this.nodes.get(id);
      if (!node) continue;

      const aspects = this.effectiveAspectsFor(node, mode, explicitAspects);
      const stop = this.traversalStopFor(node, mode, axes, aspects);
      if (!stop) continue;

      if (
        stop.reason === 'sheet-cell' ||
        node.policy.pointer === 'cell-owned' ||
        node.policy.chrome === 'cell' ||
        node.policy.selection === 'grid-cell' ||
        node.policy.keyboard === 'grid-cell'
      ) {
        return node.id;
      }
    }

    return null;
  }

  focus(id: string | null): boolean {
    if (id === null) {
      this.focusPath = [];
      this.record('focus:clear');
      return true;
    }
    if (!this.nodes.has(id)) return false;
    this.focusTo(id);
    this.record(`focus:${id}`);
    return true;
  }

  select(id: string, options: FociSelectOptions = {}): void {
    const node = this.nodes.get(id);
    if (!node) return;
    if (options.restoreSource && this.input) {
      this.closeInput(this.input.sourceId === id);
    }
    if ((node.policy.selection ?? 'single') === 'none') {
      this.focusTo(id);
      this.record(`focus:${id}`);
      return;
    }

    const scopeId = this.scopeIdFor(node);
    const scopeKind = node.scopeKind ?? this.scopeKindFor(scopeId);
    const previous = this.selections.get(scopeId);
    const anchorId = options.range
      ? (previous?.anchorId ?? previous?.headId ?? id)
      : id;
    let ids: string[];
    let range: FociRangeSnapshot | undefined;

    if (options.range && previous) {
      const computed = this.rangeBetween(scopeId, anchorId ?? id, id);
      ids = computed.ids;
      range = computed.range;
    } else if (options.additive && previous) {
      const next = new Set(previous.ids);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      ids = this.orderIds(scopeId, [...next]);
    } else {
      ids = [id];
    }

    const selection: FociSelectionSnapshot = {
      scopeId,
      scopeKind,
      headId: id,
      anchorId,
      ids,
      range,
    };
    this.selections.set(scopeId, selection);
    this.activeScopeId = scopeId;
    this.selectionActivatedAt.set(scopeId, nowMs());
    this.focusTo(id);
    this.record(`select:${scopeId}:${ids.join(',')}`);
  }

  clearInteractionState(): void {
    this.focusPath = [];
    this.selections.clear();
    this.selectionActivatedAt.clear();
    this.activeScopeId = null;
    this.hoveredId = null;
    this.input = null;
    this.overlay = null;
    this.transfer = null;
    this.record('clear:interaction');
  }

  private isPointerFocusableTarget(node: FociNode): boolean {
    if ((node.policy.selection ?? 'single') !== 'none') return true;
    if (node.target === 'action') return true;
    if (node.policy.pointer === 'content-interactive') return true;
    if (this.transfer && (node.policy.accepts?.length ?? 0) > 0) return true;
    if (
      node.target === 'field' ||
      node.target === 'value' ||
      node.target === 'range-item'
    ) {
      return true;
    }
    return (
      node.policy.traversal === 'stop' ||
      node.policy.traversal === 'boundary' ||
      node.policy.traversalModel === 'boundary'
    );
  }

  private focusTo(id: string): void {
    this.focusPath = this.pathTo(id);
  }

  private pathTo(id: string): readonly string[] {
    const cached = this.pathCache.get(id);
    if (cached) return cached;

    const path: string[] = [];
    let cursor = this.nodes.get(id);
    while (cursor) {
      path.unshift(cursor.id);
      if (cursor.parentId === null) break;
      cursor = this.nodes.get(cursor.parentId);
    }
    this.pathCache.set(id, path);
    return path;
  }

  private scopeIdFor(node: FociNode): string {
    const cached = this.scopeIdCache.get(node.id);
    if (cached) return cached;

    let scopeId: string;
    if (node.scopeId) {
      this.scopeIdCache.set(node.id, node.scopeId);
      return node.scopeId;
    }
    let cursor: FociNode | undefined = node;
    while (cursor) {
      if (
        cursor.targetScope ||
        cursor.scopeId ||
        this.isImplicitScopeRoot(cursor)
      ) {
        scopeId = cursor.scopeId ?? cursor.id;
        this.scopeIdCache.set(node.id, scopeId);
        return scopeId;
      }
      if (cursor.parentId === null) break;
      cursor = this.nodes.get(cursor.parentId);
    }
    scopeId = node.parentId ?? node.id;
    this.scopeIdCache.set(node.id, scopeId);
    return scopeId;
  }

  private scopeKindFor(scopeId: string): TargetScope {
    const node = this.nodes.get(scopeId);
    return (
      node?.targetScope ??
      node?.scopeKind ??
      (node ? this.implicitScopeKindFor(node) : undefined) ??
      'object'
    );
  }

  private isImplicitScopeRoot(node: FociNode): boolean {
    return this.implicitScopeKindFor(node) !== null;
  }

  private implicitScopeKindFor(node: FociNode): TargetScope | null {
    if (
      node.surface === 'grid' ||
      node.policy.preset === 'sheet' ||
      node.policy.preset === 'grid' ||
      node.policy.preset === 'table' ||
      node.policy.preset === 'collection' ||
      node.policy.preset === 'properties'
    ) {
      return 'range';
    }
    if (
      node.surface === 'outline' ||
      node.policy.preset === 'outline' ||
      node.policy.preset === 'page' ||
      node.policy.preset === 'notebook'
    ) {
      return 'document';
    }
    if (node.policy.preset === 'tools') return 'actions';
    if (
      node.surface === 'canvas' ||
      node.surface === 'scene' ||
      node.policy.preset === 'canvas' ||
      node.policy.preset === 'scene' ||
      node.policy.preset === 'kanban' ||
      node.policy.preset === 'dashboard'
    ) {
      return 'object';
    }
    return null;
  }

  private coordinateSpaceIdFor(id: string): string | undefined {
    let cursor = this.nodes.get(id);
    while (cursor) {
      if (cursor.coordinateSpaceId) return cursor.coordinateSpaceId;
      if (cursor.policy.coordinateSpace) return cursor.id;
      if (cursor.parentId === null) break;
      cursor = this.nodes.get(cursor.parentId);
    }
    return undefined;
  }

  private activeSelection(): FociSelectionSnapshot | null {
    if (!this.activeScopeId) return null;
    return this.selections.get(this.activeScopeId) ?? null;
  }

  private keyboardHeadId(): string | null {
    const focusId = this.focusedId;
    const active = this.activeSelection();
    if (!active?.headId) return focusId;
    if (!focusId) return active.headId;
    if (
      active.ids.includes(focusId) ||
      this.pathTo(focusId).includes(active.headId)
    ) {
      return active.headId;
    }
    return focusId;
  }

  private destinationHeadId(): string | null {
    const focusId = this.focusedId;
    if (!focusId) return this.activeSelection()?.headId ?? null;
    const active = this.activeSelection();
    if (!active?.headId) return focusId;
    if (
      active.ids.includes(focusId) ||
      this.pathTo(focusId).includes(active.headId)
    ) {
      return active.headId;
    }
    return focusId;
  }

  private selectionContaining(id: string): FociSelectionSnapshot | null {
    for (const selection of this.selections.values()) {
      if (selection.ids.includes(id)) return selection;
    }
    return null;
  }

  private isSameInputSource(targetId: string): boolean {
    return (
      this.input?.sourceId === targetId ||
      (this.input?.sourceId !== null &&
        this.input?.sourceId !== undefined &&
        this.pathTo(targetId).includes(this.input.sourceId))
    );
  }

  private commitEditor(
    ownerId: string,
    options: KeyOptions,
  ): FociDispatchResult {
    const sourceId = this.input?.sourceId ?? null;
    const direction = options.shift ? 'up' : 'down';
    this.closeInput(true);
    if (sourceId) this.advanceFrom(sourceId, direction);
    return {
      handled: true,
      ownerId,
      reason: 'commit-editor',
      intent: { type: 'commit-editor', sourceId, direction },
    };
  }

  private openEditor(
    sourceId: string,
    initialValue?: string,
  ): Extract<FociDispatchIntent, { type: 'open-editor' }> {
    const source = this.nodes.get(sourceId);
    if (!source) {
      throw new Error(`Cannot open editor for unknown surface: ${sourceId}`);
    }
    const lifted = source.policy.edit === 'lifted';
    const inputId = lifted ? `${sourceId}::edit` : `${sourceId}::inline-editor`;
    this.closePreview();
    this.input = this.createInputSession({
      kind: 'editor',
      targetId: inputId,
      keyboardOwnerId: inputId,
      sourceId,
      liftedTargetId: lifted ? inputId : undefined,
      visualSuppression: lifted ? 'source-anchor' : 'none',
      policyNode: source,
      commitModel:
        source.policy.commitModel ?? (lifted ? 'draft' : 'immediate'),
      commitTriggers:
        source.policy.commitTriggers ??
        (lifted ? ['save', 'enter'] : ['enter', 'blur']),
    });
    if (lifted) {
      this.overlay = this.createOverlay('edit', sourceId, true, inputId);
    }
    this.focusTo(sourceId);
    this.record(
      initialValue
        ? `edit:${sourceId}:seed:${initialValue}`
        : `edit:${sourceId}`,
    );
    return {
      type: 'open-editor',
      sourceId,
      editorId: inputId,
      editPolicy: source.policy.edit ?? 'none',
      seed: initialValue,
    };
  }

  private openMenu(sourceId: string | null, menuId: string): void {
    const source = sourceId ?? menuId;
    this.overlay = this.createOverlay('menu', source, true, menuId);
    this.input = this.createInputSession({
      kind: 'menu',
      targetId: menuId,
      keyboardOwnerId: menuId,
      sourceId: source,
      liftedTargetId: menuId,
      visualSuppression: 'source-anchor',
      policyNode: this.nodes.get(source),
      commitModel: 'command',
      commitTriggers: ['explicit', 'enter'],
    });
    this.record(`menu:${source}`);
  }

  private createInputSession(options: {
    kind: FociInputSession['kind'];
    targetId: string;
    keyboardOwnerId: string;
    sourceId: string | null;
    liftedTargetId?: string;
    visualSuppression: FociInputVisualSuppressionPolicy;
    policyNode?: FociNode;
    commitModel?: FociCommitModel;
    commitTriggers?: readonly FociCommitTrigger[];
    cancelTriggers?: readonly FociCancelTrigger[];
  }): FociInputSession {
    const policy = options.policyNode?.policy;
    return {
      kind: options.kind,
      id: options.targetId,
      targetId: options.targetId,
      sourceId: options.sourceId,
      liftedTargetId: options.liftedTargetId,
      keyboardOwnerId: options.keyboardOwnerId,
      visualSuppression: options.visualSuppression,
      commitPolicy: {
        model:
          options.commitModel ??
          policy?.commitModel ??
          defaultCommitModelForInputKind(options.kind),
        triggers: [
          ...(options.commitTriggers ??
            policy?.commitTriggers ??
            defaultCommitTriggersForInputKind(options.kind)),
        ],
      },
      cancelPolicy: {
        triggers: [
          ...(options.cancelTriggers ??
            policy?.cancelTriggers ??
            defaultCancelTriggersForInputKind(options.kind)),
        ],
        restoreSource: options.sourceId !== null,
      },
    };
  }

  private closeInput(restoreSource: boolean): void {
    const sourceId = this.input?.sourceId ?? null;
    this.input = null;
    if (this.overlay?.activityRole === 'input') this.overlay = null;
    if (restoreSource && sourceId && this.nodes.has(sourceId)) {
      this.focusTo(sourceId);
      const source = this.nodes.get(sourceId)!;
      const scopeId = this.scopeIdFor(source);
      if (!this.selections.get(scopeId)?.ids.includes(sourceId)) {
        this.select(sourceId);
      } else {
        this.activeScopeId = scopeId;
        this.selectionActivatedAt.set(scopeId, nowMs());
      }
    }
    this.record(sourceId ? `input:close:${sourceId}` : 'input:close');
  }

  private closePreview(): void {
    if (this.overlay?.activityRole === 'preview') {
      this.record(`preview:close:${this.overlay.sourceId}`);
      this.overlay = null;
    }
  }

  private createOverlay(
    kind: FociOverlaySession['kind'],
    sourceId: string,
    autofocus: boolean,
    targetId = `${sourceId}::${kind}`,
  ): FociOverlaySession {
    const boundaryScopeId = this.scopeIdFor(this.nodes.get(sourceId)!);
    const coordinateSpaceId = this.coordinateSpaceIdFor(sourceId);
    return {
      kind,
      sourceId,
      targetId,
      logicalParentId: sourceId,
      activityRole: autofocus ? 'input' : 'preview',
      autofocus,
      boundaryScopeId,
      coordinateSpaceId,
      coordinateRevision: coordinateSpaceId
        ? (this.coordinateRevisions.get(coordinateSpaceId) ?? 0)
        : undefined,
      placement: kind === 'tools' ? 'side' : 'bottom-start',
      focusPolicy: autofocus ? 'restore-source' : 'none',
      closePolicy: autofocus ? 'escape' : 'source-change',
    };
  }

  private moveFrom(
    sourceId: string,
    direction: FociMoveDirection,
    options: KeyOptions,
  ): FociMovementResult | null {
    const source = this.nodes.get(sourceId);
    if (!source) return null;
    const keyboard = source.policy.keyboard ?? this.keyboardFor(source);
    const scopeId = this.scopeIdFor(source);
    if (this.shouldDelegateMovement(source, keyboard)) {
      return {
        type: 'delegated',
        ownerId: this.movementOwnerIdFor(source, scopeId),
        scopeId,
        axis:
          keyboard === 'grid-cell' && source.grid
            ? 'grid'
            : movementAxisForKeyboard(keyboard),
      };
    }

    if (keyboard === 'grid-cell') {
      const targetId = this.gridStep(source, direction);
      if (!targetId) return null;
      this.closePreview();
      this.select(targetId, { range: options.shift });
      return {
        type: 'resolved',
        targetId,
        scopeId,
        axis: source.grid ? 'grid' : 'linear',
      };
    }

    const descendantTarget = this.descendantStep(source, direction);
    if (descendantTarget) {
      this.select(descendantTarget, { range: options.shift });
      return {
        type: 'resolved',
        targetId: descendantTarget,
        scopeId,
        axis: 'linear',
      };
    }

    const siblingTarget = this.linearStep(sourceId, direction, keyboard);
    if (!siblingTarget) return null;
    this.select(siblingTarget, { range: options.shift });
    return {
      type: 'resolved',
      targetId: siblingTarget,
      scopeId,
      axis: movementAxisForKeyboard(keyboard),
    };
  }

  private advanceFrom(sourceId: string, direction: 'up' | 'down'): void {
    this.moveFrom(sourceId, direction, {});
  }

  private keyboardFor(node: FociNode): FociKeyboardPolicy {
    return node.policy.keyboard ?? 'tree';
  }

  private shouldDelegateMovement(
    source: FociNode,
    keyboard: FociKeyboardPolicy,
  ): boolean {
    const policy = this.movementPolicyFor(source);
    if (policy === 'surface') return true;
    if (policy === 'engine') return false;
    return keyboard === 'canvas' || keyboard === 'scene';
  }

  private movementPolicyFor(source: FociNode): FociMovementPolicy {
    return this.compiledNodeFor(source)?.effectiveMovement ?? 'auto';
  }

  private movementOwnerIdFor(source: FociNode, scopeId: string): string {
    return this.compiledNodeFor(source)?.movementOwnerId ?? scopeId;
  }

  private gridStep(
    source: FociNode,
    direction: FociMoveDirection,
  ): string | null {
    if (!source.grid) return this.linearStep(source.id, direction, 'grid-cell');
    const scopeId = this.scopeIdFor(source);
    const delta =
      direction === 'right'
        ? { row: 0, col: 1 }
        : direction === 'left'
          ? { row: 0, col: -1 }
          : direction === 'down'
            ? { row: 1, col: 0 }
            : direction === 'up'
              ? { row: -1, col: 0 }
              : null;
    if (!delta) return null;
    const row = source.grid.row + delta.row;
    const col = source.grid.col + delta.col;
    for (const node of this.nodes.values()) {
      if (
        this.scopeIdFor(node) === scopeId &&
        node.grid?.row === row &&
        node.grid?.col === col
      ) {
        return node.id;
      }
    }
    return null;
  }

  private linearStep(
    sourceId: string,
    direction: FociMoveDirection,
    keyboard: FociKeyboardPolicy,
  ): string | null {
    const delta = linearDeltaFor(direction, keyboard);
    if (delta === 0) return null;
    const node = this.nodes.get(sourceId);
    if (!node) return null;
    const ids = this.children.get(node.parentId) ?? [];
    const index = ids.indexOf(sourceId);
    if (index < 0) return null;
    return ids[index + delta] ?? null;
  }

  private descendantStep(
    source: FociNode,
    direction: FociMoveDirection,
  ): string | null {
    if (direction === 'right') {
      return this.primaryEditableDescendantIdFor(source);
    }
    if (direction !== 'left' || !source.parentId) return null;
    const parent = this.nodes.get(source.parentId);
    if (!parent) return null;
    if (
      this.primaryEditableDescendantIdFor(parent) === source.id &&
      this.isRowValueProjectionRoot(parent)
    ) {
      return parent.id;
    }
    return null;
  }

  private primaryEditableDescendantIdFor(node: FociNode): string | null {
    if (!this.isRowValueProjectionRoot(node)) return null;
    const descendants = this.treeIds().filter((id) => {
      if (id === node.id) return false;
      return this.pathTo(id).includes(node.id);
    });
    for (const id of descendants) {
      const candidate = this.nodes.get(id);
      if (candidate && this.isEditableStop(candidate)) return id;
    }
    return null;
  }

  private rangeBetween(
    scopeId: string,
    anchorId: string,
    headId: string,
  ): { ids: string[]; range?: FociRangeSnapshot } {
    const anchor = this.nodes.get(anchorId);
    const head = this.nodes.get(headId);
    if (anchor?.grid && head?.grid) {
      const minRow = Math.min(anchor.grid.row, head.grid.row);
      const maxRow = Math.max(anchor.grid.row, head.grid.row);
      const minCol = Math.min(anchor.grid.col, head.grid.col);
      const maxCol = Math.max(anchor.grid.col, head.grid.col);
      const ids = [...this.nodes.values()]
        .filter((node) => {
          return (
            this.scopeIdFor(node) === scopeId &&
            node.grid &&
            node.grid.row >= minRow &&
            node.grid.row <= maxRow &&
            node.grid.col >= minCol &&
            node.grid.col <= maxCol
          );
        })
        .sort(compareGridNodes)
        .map((node) => node.id);
      return {
        ids,
        range: {
          axis: 'grid',
          start: anchor.grid,
          end: head.grid,
          normalized: { minRow, maxRow, minCol, maxCol },
        },
      };
    }

    const ids = this.orderIds(scopeId, [anchorId, headId]);
    return {
      ids,
      range: { axis: 'linear', start: anchorId, end: headId, normalized: ids },
    };
  }

  private orderIds(scopeId: string, ids: readonly string[]): string[] {
    const wanted = new Set(ids);
    const ordered = this.treeIds().filter((id) => {
      const node = this.nodes.get(id);
      return node && this.scopeIdFor(node) === scopeId && wanted.has(id);
    });
    return ordered.length > 0 ? ordered : [...ids];
  }

  private destinationFor(
    targetId: string,
    operation: 'move' | 'copy' | 'connect',
  ): FociDestinationSnapshot | null {
    const target = this.nodes.get(targetId);
    if (!target) return null;
    const accepts = target.policy.accepts ?? [];
    const payloadType = this.transfer?.origin.ids
      .map((id) => this.nodes.get(id)?.policy.payloadType)
      .find(Boolean);
    if (accepts.length > 0 && payloadType && !accepts.includes(payloadType)) {
      return null;
    }
    if (accepts.length === 0 && target.policy.selection === 'none') {
      return null;
    }
    return {
      targetId,
      targetKind: this.destinationKindFor(target),
      accepts,
      operation,
    };
  }

  private destinationKindFor(
    target: FociNode,
  ): FociDestinationSnapshot['targetKind'] {
    if (target.surface === 'outline') return 'nest-child';
    const presetKind = this.compiledNodeFor(target)?.destinationKindDefault;
    if (presetKind === 'kanban-gap') {
      return target.target === 'structure' ? 'kanban-gap' : 'lane-end';
    }
    if (presetKind) return presetKind;
    if (target.surface === 'layout') return 'dashboard-slot';
    if (
      target.policy.accepts?.includes('connector-handle') ||
      this.ancestorHasSurface(target, 'connection')
    ) {
      return 'connect-handle';
    }
    if (target.surface === 'canvas') return 'drop-world';
    if (target.surface === 'grid') return 'grid-span';
    return 'drop';
  }

  private clearActiveScope(): boolean {
    if (!this.activeScopeId) return false;
    return this.clearSelectionScope(this.activeScopeId, {
      focusId: this.focusedId,
      reason: 'clear-active-scope',
      intentType: 'dismiss-selection',
    }).handled;
  }

  private clearSelectionScope(
    scopeId: string,
    options: {
      focusId: string | null;
      reason:
        | 'clear-active-scope'
        | 'dismiss-focused-selection'
        | 'escape-up-level'
        | 'click-away-cancel';
      intentType: 'dismiss-selection' | 'go-up-level';
    },
  ): FociDispatchResult {
    const selection = this.selections.get(scopeId);
    if (!selection) {
      return {
        handled: false,
        ownerId: options.focusId,
        reason: 'nothing-to-dismiss',
      };
    }

    const wasActive = this.activeScopeId === scopeId;
    const parentScopeId = this.parentSelectionScopeFor(selection);
    this.selections.delete(scopeId);
    this.selectionActivatedAt.delete(scopeId);

    if (wasActive) {
      this.activeScopeId =
        parentScopeId ?? latestSelectionScope(this.selections);
      this.focusAfterSelectionDismiss(selection, this.activeScopeId);
      if (this.activeScopeId) {
        this.selectionActivatedAt.set(this.activeScopeId, nowMs());
      }
    } else if (this.activeScopeId && !this.selections.has(this.activeScopeId)) {
      this.activeScopeId = latestSelectionScope(this.selections);
    }

    this.record(`clear:${selection.scopeId}`);

    return {
      handled: true,
      ownerId: selection.headId ?? options.focusId,
      reason: options.reason,
      intent:
        options.intentType === 'go-up-level'
          ? {
              type: 'go-up-level',
              sourceScopeId: selection.scopeId,
              targetScopeId: this.activeScopeId,
              focusId: options.focusId,
            }
          : {
              type: 'dismiss-selection',
              scopeId: selection.scopeId,
              focusId: options.focusId,
            },
    };
  }

  private focusAfterSelectionDismiss(
    selection: FociSelectionSnapshot,
    nextActiveScopeId: string | null,
  ): void {
    const nextSelection = nextActiveScopeId
      ? this.selections.get(nextActiveScopeId)
      : null;
    if (nextSelection?.headId) {
      this.focusTo(nextSelection.headId);
      return;
    }

    const scopeNode = this.nodes.get(selection.scopeId);
    if (scopeNode && this.isPointerFocusableTarget(scopeNode)) {
      this.focusTo(scopeNode.id);
      return;
    }

    const head = selection.headId ? this.nodes.get(selection.headId) : null;
    if (head?.parentId) {
      const parent = this.nodes.get(head.parentId);
      if (parent && this.isPointerFocusableTarget(parent)) {
        this.focusTo(parent.id);
        return;
      }
    }
    this.focusPath = [];
  }

  private parentSelectionScopeFor(
    selection: FociSelectionSnapshot,
  ): string | null {
    const headId = selection.headId;
    if (!headId) return null;
    const ancestorIds = this.pathTo(headId).slice(0, -1).reverse();
    for (const ancestorId of ancestorIds) {
      const ancestorSelection = this.selectionContaining(ancestorId);
      if (
        ancestorSelection &&
        ancestorSelection.scopeId !== selection.scopeId &&
        this.selections.has(ancestorSelection.scopeId)
      ) {
        return ancestorSelection.scopeId;
      }
    }
    return null;
  }

  private selectionScopeForFocus(focusId: string): string | null {
    const focusNode = this.nodes.get(focusId);
    if (focusNode) {
      const directScopeId = this.scopeIdFor(focusNode);
      if (this.selections.has(directScopeId)) return directScopeId;
    }

    const path = this.pathTo(focusId).slice().reverse();
    for (const id of path) {
      const selection = this.selectionContaining(id);
      if (selection && this.selections.has(selection.scopeId)) {
        return selection.scopeId;
      }
    }
    return null;
  }

  private selectionScopeForCancel(
    options: FociCancelOptions,
    focusId: string | null,
  ): string | null {
    if (options.scopeId && this.selections.has(options.scopeId)) {
      return options.scopeId;
    }

    const targetId =
      options.targetId && this.nodes.has(options.targetId)
        ? options.targetId
        : null;
    if (targetId) {
      const scopesUnderTarget = [...this.selections.values()]
        .filter((selection) => {
          return (
            selection.headId !== null &&
            this.pathTo(selection.headId).includes(targetId)
          );
        })
        .sort((left, right) => {
          return (
            this.pathTo(right.headId ?? '').length -
            this.pathTo(left.headId ?? '').length
          );
        });
      if (
        this.activeScopeId &&
        scopesUnderTarget.some((selection) => {
          return selection.scopeId === this.activeScopeId;
        })
      ) {
        return this.activeScopeId;
      }
      if (scopesUnderTarget[0]) return scopesUnderTarget[0].scopeId;
    }

    if (focusId) {
      const focusedScopeId = this.selectionScopeForFocus(focusId);
      if (focusedScopeId) return focusedScopeId;
    }

    const active = this.activeSelection();
    if (active) return active.scopeId;

    return latestSelectionScope(this.selections);
  }

  private resolveFocusId(focusId: string | null | undefined): string | null {
    if (focusId && this.nodes.has(focusId)) return focusId;
    return this.focusedId;
  }

  private layers(): FociActivityLayerSnapshot[] {
    const layers: FociActivityLayerSnapshot[] = [];
    if (this.input) {
      layers.push({
        role: 'input',
        id: this.input.id,
        sourceId: this.input.sourceId ?? undefined,
        keyOwner: true,
        visualTier: 'primary',
      });
      if (this.input.sourceId) {
        layers.push({
          role: 'source',
          id: this.input.sourceId,
          keyOwner: false,
          visualTier: 'source',
        });
      }
    } else {
      const active = this.activeSelection();
      if (active?.headId) {
        layers.push({
          role: 'selection',
          id: active.headId,
          scopeId: active.scopeId,
          keyOwner: true,
          visualTier: 'primary',
        });
      }
    }

    if (this.overlay?.activityRole === 'preview') {
      layers.push({
        role: 'preview',
        id: this.overlay.targetId,
        sourceId: this.overlay.sourceId,
        keyOwner: false,
        visualTier: 'preview',
      });
    }

    if (this.transfer) {
      if (this.transfer.origin.headId) {
        layers.push({
          role: 'origin',
          id: this.transfer.origin.headId,
          scopeId: this.transfer.origin.scopeId,
          keyOwner: false,
          visualTier: 'source',
        });
      }
      const destination = this.visibleTransferDestination();
      if (destination) {
        layers.push({
          role: 'destination',
          id: destination.targetId,
          keyOwner: false,
          visualTier: 'destination',
        });
      }
    }

    if (this.hoveredId) {
      layers.push({
        role: 'hover',
        id: this.hoveredId,
        keyOwner: false,
        visualTier: 'preview',
      });
    }

    for (const [scopeId, selection] of this.selections) {
      if (scopeId === this.activeScopeId) continue;
      if (!selection.headId) continue;
      layers.push({
        role: 'context',
        id: selection.headId,
        scopeId,
        keyOwner: false,
        visualTier: 'context',
      });
    }
    return layers;
  }

  private projectedLayerRoles(): ReadonlyMap<
    string,
    readonly FociActivityRole[]
  > {
    const rolesById = new Map<string, Set<FociActivityRole>>();
    for (const layer of this.layers()) {
      if (this.nodes.has(layer.id)) {
        addProjectionLayerRole(rolesById, layer.id, layer.role);
      }
      if (layer.sourceId && this.nodes.has(layer.sourceId)) {
        addProjectionLayerRole(rolesById, layer.sourceId, 'source');
      }
    }
    return new Map(
      [...rolesById].map(([id, roles]) => [id, [...roles]] as const),
    );
  }

  private projectionAdornmentsFor(
    node: FociNode,
    options: {
      mode: FociMode;
      stop: FociTraversalStop | undefined;
      layerRoles: readonly FociActivityRole[];
      rangeIds: ReadonlySet<string>;
    },
  ): readonly FociProjectionAdornment[] {
    const adornments = new Set<FociProjectionAdornment>();
    if (this.focusedId === node.id) adornments.add('focus');
    if (options.rangeIds.has(node.id)) adornments.add('range');
    if (options.stop?.reason === 'receiver') adornments.add('receiver');

    for (const role of options.layerRoles) {
      if (role === 'input' || role === 'preview') continue;
      if (role === 'selection' && this.focusedId === node.id) continue;
      adornments.add(role);
      if (
        role === 'hover' &&
        (options.mode === 'inspect' || options.mode === 'debug')
      ) {
        adornments.add('inspect');
      }
    }
    return [...adornments];
  }

  private projectionDecals(
    traversal: FociTraversalSet,
    mode: FociMode,
  ): readonly FociProjectionDecal[] {
    const decals: FociProjectionDecal[] = [];
    const activeSelection = this.activeSelection();

    for (const stop of traversal.stops) {
      if (stop.reason === 'receiver') {
        decals.push({
          kind: 'receiver',
          ids: [stop.id],
          label: `Drop target ${stop.id}`,
        });
      }
    }

    if (activeSelection && activeSelection.ids.length > 1) {
      decals.push({
        kind: 'range',
        ids: [...activeSelection.ids],
        label: `Range ${activeSelection.ids.join(', ')}`,
      });
    }

    for (const layer of this.layers()) {
      if (layer.role === 'input' || layer.role === 'preview') continue;
      if (layer.role === 'selection' && layer.id === this.focusedId) continue;
      if (layer.role === 'hover' || layer.role === 'inspect') continue;
      if (!this.nodes.has(layer.id)) continue;
      decals.push({
        kind: layer.role,
        ids: [layer.id],
        label: `${layer.role} ${layer.id}`,
      });
    }

    if (
      this.hoveredId &&
      this.nodes.has(this.hoveredId) &&
      (mode === 'inspect' || mode === 'debug')
    ) {
      decals.push({
        kind: 'inspect',
        ids: [this.hoveredId],
        label: `Inspect ${this.hoveredId}`,
      });
    }

    if (this.focusedId && this.nodes.has(this.focusedId)) {
      decals.push({
        kind: 'focus',
        ids: [this.focusedId],
        label: `Focus ${this.focusedId}`,
      });
    }

    if (this.input?.sourceId && this.nodes.has(this.input.sourceId)) {
      decals.push({
        kind: 'edit-anchor',
        ids: [this.input.sourceId],
        label: `Edit anchor ${this.input.sourceId}`,
      });
    }

    return decals;
  }

  private resolveProjectionVisuals(options: {
    mode: FociMode;
    nodes: readonly FociProjectionNode[];
    decals: readonly FociProjectionDecal[];
  }): FociProjectionVisualResolution {
    const adornmentsById = new Map<string, Set<FociVisualAdornment>>();
    const suppressedById = new Map<string, Set<FociProjectionAdornment>>();
    for (const node of options.nodes) {
      adornmentsById.set(
        node.id,
        new Set<FociVisualAdornment>(node.adornments),
      );
      suppressedById.set(node.id, new Set<FociProjectionAdornment>());
    }

    const rawDecals = [...options.decals];
    const suppressedDecals: FociProjectionDecal[] = [];
    let visualDecals = rawDecals;
    const primary = this.visualPrimaryFor(options);

    if (options.mode === 'debug') {
      return {
        nodeVisuals: buildNodeVisuals(adornmentsById, suppressedById),
        decals: rawDecals,
        suppressedDecals: [],
        primary,
      };
    }

    const suppressAdornment = (
      id: string,
      kind: FociProjectionAdornment,
    ): void => {
      const adornments = adornmentsById.get(id);
      if (!adornments?.has(kind)) return;
      adornments.delete(kind);
      suppressedById.get(id)?.add(kind);
    };
    const suppressAdornmentsEverywhere = (
      kinds: readonly FociProjectionAdornment[],
    ): void => {
      for (const node of options.nodes) {
        for (const kind of kinds) suppressAdornment(node.id, kind);
      }
    };
    const addAdornment = (id: string, kind: FociVisualAdornment): void => {
      adornmentsById.get(id)?.add(kind);
    };
    const suppressDecals = (
      predicate: (decal: FociProjectionDecal) => boolean,
    ): void => {
      const kept: FociProjectionDecal[] = [];
      for (const decal of visualDecals) {
        if (predicate(decal)) suppressedDecals.push(decal);
        else kept.push(decal);
      }
      visualDecals = kept;
    };

    if (this.transferLocksVisuals()) {
      suppressAdornmentsEverywhere([
        'focus',
        'selection',
        'range',
        'context',
        'hover',
        'inspect',
      ]);
      suppressDecals(
        (decal) =>
          decal.kind === 'focus' ||
          decal.kind === 'selection' ||
          decal.kind === 'range' ||
          decal.kind === 'context' ||
          decal.kind === 'hover' ||
          decal.kind === 'inspect',
      );
    } else if (
      this.input?.sourceId &&
      this.input.visualSuppression === 'source-anchor'
    ) {
      const sourceId = this.input.sourceId;
      suppressAdornmentsEverywhere(['range', 'context']);
      for (const kind of [
        'focus',
        'selection',
        'source',
        'origin',
        'destination',
      ] as const) {
        suppressAdornment(sourceId, kind);
      }
      addAdornment(sourceId, 'edit-anchor');
      suppressDecals(
        (decal) =>
          decal.kind === 'range' ||
          decal.kind === 'context' ||
          decal.kind === 'source' ||
          decal.kind === 'origin' ||
          decal.kind === 'selection' ||
          (decal.kind === 'focus' && decal.ids.includes(sourceId)),
      );
    } else if (this.hoveredId && options.mode === 'inspect') {
      suppressAdornmentsEverywhere(['focus', 'selection', 'range', 'context']);
      suppressDecals(
        (decal) =>
          decal.kind === 'focus' ||
          decal.kind === 'selection' ||
          decal.kind === 'range' ||
          decal.kind === 'context',
      );
    } else if (primary?.kind === 'range') {
      suppressAdornmentsEverywhere(['focus', 'selection', 'context']);
      suppressDecals(
        (decal) =>
          decal.kind === 'focus' ||
          decal.kind === 'selection' ||
          decal.kind === 'context',
      );
    }

    const activeSelection = this.activeSelection();
    if (
      activeSelection?.headId &&
      this.focusedId &&
      activeSelection.headId !== this.focusedId &&
      this.pathTo(activeSelection.headId).includes(this.focusedId)
    ) {
      suppressAdornment(this.focusedId, 'focus');
      suppressDecals(
        (decal) =>
          decal.kind === 'focus' && decal.ids.includes(this.focusedId!),
      );
    }

    return {
      nodeVisuals: buildNodeVisuals(adornmentsById, suppressedById),
      decals: visualDecals,
      suppressedDecals,
      primary,
    };
  }

  private resolveAdornmentPresentation(
    id: string,
    visualAdornments: readonly FociVisualAdornment[],
  ): {
    surfaceAdornments: readonly FociVisualAdornment[];
    decalAdornments: readonly FociProjectionAdornment[];
    presentation: Readonly<
      Partial<Record<FociProjectionAdornment, FociAdornmentPresentation>>
    >;
  } {
    const node = this.nodes.get(id);
    const surfaceAdornments: FociVisualAdornment[] = [];
    const decals: FociProjectionAdornment[] = [];
    const presentation: Partial<
      Record<FociProjectionAdornment, FociAdornmentPresentation>
    > = {};

    for (const adornment of visualAdornments) {
      const resolved = this.presentationForAdornment(node, adornment);
      presentation[adornment] = resolved;
      if (resolved === 'surface' || resolved === 'both') {
        surfaceAdornments.push(adornment);
      }
      if (resolved === 'decal' || resolved === 'both') decals.push(adornment);
    }

    return {
      surfaceAdornments,
      decalAdornments: decals,
      presentation,
    };
  }

  private presentationForAdornment(
    node: FociNode | undefined,
    adornment: FociProjectionAdornment,
  ): FociAdornmentPresentation {
    const explicit = node?.policy.adornments?.[adornment];
    if (explicit && explicit !== 'auto') return explicit;

    if (
      node?.surface === 'row' &&
      (adornment === 'focus' ||
        adornment === 'selection' ||
        adornment === 'source')
    ) {
      return 'surface';
    }

    if (
      adornment === 'range' ||
      adornment === 'receiver' ||
      adornment === 'inspect' ||
      adornment === 'edit-anchor' ||
      adornment === 'origin' ||
      adornment === 'destination'
    ) {
      return 'decal';
    }

    if (
      adornment === 'focus' ||
      adornment === 'selection' ||
      adornment === 'source'
    ) {
      return this.surfaceNeedsExternalSelectionChrome(node)
        ? 'decal'
        : 'surface';
    }

    return 'surface';
  }

  private shouldRenderDecal(decal: FociProjectionDecal): boolean {
    if (decal.ids.length === 0) return false;
    return decal.ids.some((id) => {
      const presentation = this.presentationForAdornment(
        this.nodes.get(id),
        decal.kind,
      );
      return presentation === 'decal' || presentation === 'both';
    });
  }

  private surfaceNeedsExternalSelectionChrome(
    node: FociNode | undefined,
  ): boolean {
    if (!node) return false;
    return (
      node.target === 'range-item' ||
      node.policy.selection === 'grid-cell' ||
      node.policy.selection === 'object' ||
      node.policy.selection === 'range' ||
      node.policy.keyboard === 'grid-cell' ||
      node.policy.chrome === 'cell' ||
      node.policy.aspects?.includes('cell') === true
    );
  }

  private visualPrimaryFor(options: {
    mode: FociMode;
    decals: readonly FociProjectionDecal[];
  }): FociProjectionVisualPrimary | null {
    const destination = this.visibleTransferDestination();
    const transfer = this.transfer;
    if (destination && transfer) {
      return {
        kind: 'transfer-destination',
        id: destination.targetId,
        sourceId: transfer.origin.headId ?? undefined,
      };
    }
    if (this.transfer?.origin.headId) {
      return {
        kind: 'transfer-origin',
        id: this.transfer.origin.headId,
      };
    }
    if (this.input) {
      return {
        kind: 'input',
        id: this.input.id,
        sourceId: this.input.sourceId ?? undefined,
      };
    }
    if (
      this.hoveredId &&
      (options.mode === 'inspect' || options.mode === 'debug')
    ) {
      return { kind: 'inspect', id: this.hoveredId };
    }
    const range = options.decals.find((decal) => decal.kind === 'range');
    if (range?.ids[0]) return { kind: 'range', id: range.ids[0] };
    if (this.focusedId) return { kind: 'focus', id: this.focusedId };
    return null;
  }

  private visibleTransferDestination(): FociDestinationSnapshot | null {
    if (!this.transfer?.destination) return null;

    switch (this.transfer.kind) {
      case 'drag':
        return this.transfer.movedPastThreshold
          ? this.transfer.destination
          : null;
      case 'place':
      case 'connect':
      case 'resize':
      case 'reorder':
      case 'cut':
        return this.transfer.destination;
      case 'copy':
        return null;
    }
  }

  private transferLocksVisuals(): boolean {
    if (!this.transfer) return false;
    if (this.visibleTransferDestination()) return true;
    return this.transfer.kind !== 'copy';
  }

  private treeSnapshot(): FociNodeSnapshot[] {
    return this.treeIds().map((id) => {
      const node = this.nodes.get(id)!;
      return {
        ...node,
        children: this.children.get(id) ?? [],
        focusPath: this.focusPath.includes(id),
        focused: this.focusedId === id,
        hovered: this.hoveredId === id,
        selected: this.selectionContaining(id) !== null,
      };
    });
  }

  private treeIds(): string[] {
    const ids: string[] = [];
    const visit = (parentId: string | null): void => {
      for (const childId of this.children.get(parentId) ?? []) {
        ids.push(childId);
        visit(childId);
      }
    };
    visit(null);
    return ids;
  }

  private stepTraversal(delta: 1 | -1, options: FociTraversalOptions): boolean {
    const nextId = this.stepTraversalId(this.focusedId, delta, options);
    if (!nextId) return false;
    this.focusTraversalStop(nextId);
    return true;
  }

  private stepTraversalId(
    id: string | null,
    delta: 1 | -1,
    options: FociTraversalOptions,
  ): string | null {
    const ids = this.traversalSet(options).ids;
    if (ids.length === 0) return null;
    if (!id) return delta > 0 ? ids[0]! : ids[ids.length - 1]!;

    let index = ids.indexOf(id);
    if (index < 0) {
      const path = this.pathTo(id);
      index =
        path
          .slice()
          .reverse()
          .map((pathId) => ids.indexOf(pathId))
          .find((candidate) => candidate >= 0) ?? -1;
    }
    if (index < 0) return delta > 0 ? ids[0]! : ids[ids.length - 1]!;
    return ids[index + delta] ?? null;
  }

  private focusTraversalStop(id: string): void {
    const node = this.nodes.get(id);
    if (!node) return;
    if ((node.policy.selection ?? 'single') === 'none') {
      this.focusTo(id);
      this.record(`traverse:${id}`);
      return;
    }
    this.select(id);
  }

  private traversalStopFor(
    node: FociNode,
    mode: FociMode,
    axes: readonly FociTraversalAxis[],
    aspects: ReadonlySet<FociPresetAspect>,
  ): FociTraversalStop | null {
    const target = node.target;
    const scopeId = this.scopeIdFor(node);
    const forced = node.policy.traversal === 'stop';
    const interactive = node.policy.pointer === 'content-interactive';
    const action = target === 'action' || interactive;

    if (forced) {
      return this.makeTraversalStop(node, scopeId, 'forced');
    }
    if (axes.includes('debug')) {
      return this.makeTraversalStop(node, scopeId, 'debug');
    }
    if (
      node.policy.traversal === 'boundary' ||
      node.policy.traversalModel === 'boundary'
    ) {
      return this.makeTraversalStop(node, scopeId, 'boundary');
    }
    if (this.isDocumentItemStop(node, mode)) {
      return this.makeTraversalStop(node, scopeId, 'document-item');
    }
    if (this.isToolControlStop(node, mode)) {
      return this.makeTraversalStop(node, scopeId, 'tool-control');
    }
    if (action && axes.includes('actions')) {
      return this.makeTraversalStop(
        node,
        scopeId,
        interactive ? 'interactive' : 'action',
      );
    }
    if (
      this.isReceiverStop(node, mode, aspects) &&
      axes.includes('receivers')
    ) {
      return this.makeTraversalStop(node, scopeId, 'receiver');
    }
    if (
      this.isSheetCellStop(node, aspects) &&
      (mode === 'use' || mode === 'change')
    ) {
      return this.makeTraversalStop(node, scopeId, 'sheet-cell');
    }
    if (this.isObjectStop(node) && axes.includes('objects')) {
      return this.makeTraversalStop(node, scopeId, 'object');
    }
    if (this.isRowStop(node) && (mode === 'use' || mode === 'change')) {
      return this.makeTraversalStop(node, scopeId, 'row');
    }
    if (mode === 'change' && this.isEditableStop(node)) {
      return this.makeTraversalStop(node, scopeId, 'editable');
    }
    if (mode === 'inspect' && this.isInspectableStop(node)) {
      return this.makeTraversalStop(node, scopeId, 'inspect');
    }
    if (aspects.has('inspect') && this.isMaterialStop(node)) {
      return this.makeTraversalStop(node, scopeId, 'inspect');
    }
    return null;
  }

  private makeTraversalStop(
    node: FociNode,
    scopeId: string,
    reason: FociTraversalStopReason,
  ): FociTraversalStop {
    return {
      id: node.id,
      surface: node.surface,
      target: node.target,
      scopeId,
      reason,
    };
  }

  private effectiveAspectsFor(
    node: FociNode,
    mode: FociMode,
    explicit: ReadonlySet<FociPresetAspect>,
  ): ReadonlySet<FociPresetAspect> {
    const aspects = new Set<FociPresetAspect>(
      this.compiledNodeFor(node)?.inheritedAspectsByMode[mode] ?? [],
    );
    for (const aspect of explicit) aspects.add(aspect);
    return aspects;
  }

  private isReceiverStop(
    node: FociNode,
    mode: FociMode,
    aspects: ReadonlySet<FociPresetAspect>,
  ): boolean {
    if ((node.policy.accepts?.length ?? 0) === 0) return false;
    if (this.transfer) return true;
    if (mode !== 'change') return false;
    return (
      aspects.has('place') ||
      aspects.has('reorder') ||
      aspects.has('resize') ||
      aspects.has('connect')
    );
  }

  private isSheetCellStop(
    node: FociNode,
    aspects: ReadonlySet<FociPresetAspect>,
  ): boolean {
    if (node.surface !== 'cell') return false;
    const sheetCellDefault = this.compiledNodeFor(node)?.sheetCellDefault;
    if (sheetCellDefault === false && !aspects.has('sheet')) {
      return false;
    }
    return (
      node.grid !== undefined ||
      sheetCellDefault === true ||
      aspects.has('sheet') ||
      node.policy.selection === 'grid-cell' ||
      node.policy.chrome === 'cell' ||
      node.policy.keyboard === 'grid-cell'
    );
  }

  private isObjectStop(node: FociNode): boolean {
    return (
      node.target === 'object' &&
      (node.surface === 'frame' ||
        node.surface === 'connection' ||
        node.policy.selection === 'single' ||
        node.policy.selection === 'object')
    );
  }

  private isRowStop(node: FociNode): boolean {
    if (node.surface !== 'row') return false;
    if (
      node.policy.selection === 'row' &&
      (node.target === 'object' || node.target === 'range-item')
    ) {
      return true;
    }
    return (
      this.compiledNodeFor(node)?.rowStopDefault === true ||
      this.ancestorHasSurface(node, 'outline')
    );
  }

  private isRowValueProjectionRoot(node: FociNode): boolean {
    return (
      node.surface === 'row' &&
      this.compiledNodeFor(node)?.rowValueProjectionDefault === true &&
      (node.target === 'range-item' || node.target === 'field')
    );
  }

  private isEditableStop(node: FociNode): boolean {
    if (node.policy.pointer === 'content-interactive') return true;
    return (node.policy.edit ?? 'none') !== 'none';
  }

  private isDocumentItemStop(node: FociNode, mode: FociMode): boolean {
    if (mode === 'debug') return false;
    if (this.parentTraversalModel(node) !== 'document') return false;
    if (node.policy.traversal === 'skip') return false;
    return (
      node.target === 'object' ||
      node.target === 'field' ||
      node.target === 'value' ||
      node.target === 'range-item' ||
      node.policy.traversal === 'stop'
    );
  }

  private isToolControlStop(node: FociNode, mode: FociMode): boolean {
    if (mode === 'debug') return false;
    if (this.nearestTraversalModel(node) !== 'tools') return false;
    return (
      node.target === 'action' ||
      node.policy.pointer === 'content-interactive' ||
      this.isEditableStop(node)
    );
  }

  private isMaterialStop(node: FociNode): boolean {
    return (
      node.target === 'object' ||
      node.target === 'field' ||
      node.target === 'value' ||
      node.target === 'range-item'
    );
  }

  private isInspectableStop(node: FociNode): boolean {
    if (node.parentId === null && node.surface === 'space') return false;
    if (node.policy.pointer === 'preview-only') return false;
    return true;
  }

  private isAutoBoundary(
    node: FociNode,
    _mode: FociMode,
    _aspects: ReadonlySet<FociPresetAspect>,
  ): boolean {
    if (node.policy.traversal === 'boundary') return true;
    if (node.policy.traversalModel === 'boundary') return true;
    if (node.surface === 'pane' || node.surface === 'plane') return true;
    if (this.parentTraversalModel(node) === 'document') {
      return this.childrenOf(node.id).length > 0;
    }
    return (
      node.surface === 'frame' &&
      this.childrenOf(node.id).length > 0 &&
      (this.ancestorHasSurface(node, 'canvas') ||
        this.ancestorHasSurface(node, 'scene'))
    );
  }

  private isActivatableBoundary(node: FociNode): boolean {
    if (this.childrenOf(node.id).length === 0) return false;
    return (
      node.policy.traversal === 'boundary' ||
      node.policy.traversalModel === 'boundary' ||
      this.isAutoBoundary(node, 'use', new Set())
    );
  }

  private parentTraversalModel(node: FociNode): FociTraversalModel | null {
    if (node.parentId === null) return null;
    return this.compiledNodeFor(node.parentId)?.inheritedTraversalModel ?? null;
  }

  private nearestTraversalModel(node: FociNode): FociTraversalModel | null {
    if (node.parentId === null) return null;
    return this.compiledNodeFor(node.parentId)?.inheritedTraversalModel ?? null;
  }

  private ancestorHasSurface(node: FociNode, surface: LadderSurface): boolean {
    for (const pathId of this.pathTo(node.id)) {
      if (pathId === node.id) continue;
      if (this.nodes.get(pathId)?.surface === surface) return true;
    }
    return false;
  }

  private childrenOf(id: string): readonly string[] {
    return this.children.get(id) ?? [];
  }

  private record(message: string): void {
    this.logEntries.push(message);
  }
}

export function createFociStore(
  registrations: readonly FociNodeRegistration[] = [],
): FociStore {
  return new FociStore().load(registrations);
}

function traversalAxesFor(
  mode: FociMode,
  inspect = false,
): readonly FociTraversalAxis[] {
  if (mode === 'debug') return ['debug'];
  if (mode === 'inspect' || inspect) {
    return ['actions', 'material', 'objects'];
  }
  if (mode === 'change') {
    return ['actions', 'material', 'editable', 'objects', 'receivers'];
  }
  return ['actions', 'material', 'objects'];
}

function compareGridNodes(a: FociNode, b: FociNode): number {
  const rowDelta = (a.grid?.row ?? 0) - (b.grid?.row ?? 0);
  if (rowDelta !== 0) return rowDelta;
  return (a.grid?.col ?? 0) - (b.grid?.col ?? 0);
}

function addProjectionLayerRole(
  rolesById: Map<string, Set<FociActivityRole>>,
  id: string,
  role: FociActivityRole,
): void {
  const roles = rolesById.get(id) ?? new Set<FociActivityRole>();
  roles.add(role);
  rolesById.set(id, roles);
}

function buildNodeVisuals(
  adornmentsById: ReadonlyMap<string, ReadonlySet<FociVisualAdornment>>,
  suppressedById: ReadonlyMap<string, ReadonlySet<FociProjectionAdornment>>,
): ReadonlyMap<string, FociNodeVisualResolution> {
  return new Map(
    [...adornmentsById].map(([id, adornments]) => [
      id,
      {
        adornments: [...adornments],
        suppressed: [...(suppressedById.get(id) ?? [])],
      },
    ]),
  );
}

function isArrowKey(key: string): boolean {
  return (
    key === 'ArrowRight' ||
    key === 'ArrowLeft' ||
    key === 'ArrowUp' ||
    key === 'ArrowDown'
  );
}

function directionFromArrowKey(key: string): FociMoveDirection {
  switch (key) {
    case 'ArrowRight':
      return 'right';
    case 'ArrowLeft':
      return 'left';
    case 'ArrowUp':
      return 'up';
    case 'ArrowDown':
      return 'down';
    default:
      throw new Error(`Not an arrow key: ${key}`);
  }
}

function linearDeltaFor(
  direction: FociMoveDirection,
  keyboard: FociKeyboardPolicy,
): -1 | 0 | 1 {
  if (keyboard === 'grid-cell') {
    return direction === 'left' || direction === 'up' ? -1 : 1;
  }
  if (keyboard === 'row-list' || keyboard === 'outline') {
    if (direction === 'up') return -1;
    if (direction === 'down') return 1;
    return 0;
  }
  if (keyboard === 'tree') {
    if (direction === 'up') return -1;
    if (direction === 'down') return 1;
    return 0;
  }
  if (keyboard === 'canvas' || keyboard === 'scene') {
    return direction === 'left' || direction === 'up' ? -1 : 1;
  }
  return 0;
}

function movementAxisForKeyboard(keyboard: FociKeyboardPolicy): FociMoveAxis {
  if (keyboard === 'canvas' || keyboard === 'scene') return 'spatial';
  return 'linear';
}

function isPrintableKey(key: string): boolean {
  return key.length === 1 && key >= ' ' && key !== '\u007f';
}

function isOutsideClickTrigger(trigger: FociCancelTrigger): boolean {
  return trigger === 'outside-click' || trigger === 'click-away';
}

function defaultCommitModelForInputKind(
  kind: FociInputSession['kind'],
): FociCommitModel {
  switch (kind) {
    case 'control':
      return 'immediate';
    case 'menu':
    case 'tools':
    case 'drag':
      return 'command';
    case 'editor':
    default:
      return 'draft';
  }
}

function defaultCommitTriggersForInputKind(
  kind: FociInputSession['kind'],
): readonly FociCommitTrigger[] {
  switch (kind) {
    case 'control':
      return ['change'];
    case 'drag':
      return ['release'];
    case 'menu':
    case 'tools':
      return ['enter', 'explicit'];
    case 'editor':
    default:
      return ['enter', 'save'];
  }
}

function defaultCancelTriggersForInputKind(
  kind: FociInputSession['kind'],
): readonly FociCancelTrigger[] {
  switch (kind) {
    case 'control':
      return ['escape', 'source-change'];
    case 'drag':
      return ['escape'];
    case 'menu':
    case 'tools':
    case 'editor':
    default:
      return ['escape', 'outside-click', 'source-change'];
  }
}

function cloneSelection(
  selection: FociSelectionSnapshot,
): FociSelectionSnapshot {
  return {
    ...selection,
    ids: [...selection.ids],
    range: selection.range
      ? {
          ...selection.range,
          start: cloneUnknown(selection.range.start),
          end: cloneUnknown(selection.range.end),
          normalized: cloneUnknown(selection.range.normalized),
        }
      : undefined,
  };
}

function cloneUnknown<T>(value: T): T {
  if (Array.isArray(value)) return [...value] as T;
  if (value && typeof value === 'object') return { ...value } as T;
  return value;
}

function uniqueKnownPath<T>(
  path: readonly string[],
  nodes: ReadonlyMap<string, T>,
): string[] {
  const ids: string[] = [];
  const seen = new Set<string>();
  for (const id of path) {
    if (seen.has(id) || !nodes.has(id)) continue;
    seen.add(id);
    ids.push(id);
  }
  return ids;
}

function latestSelectionScope(
  selections: ReadonlyMap<string, FociSelectionSnapshot>,
): string | null {
  let latest: string | null = null;
  for (const scopeId of selections.keys()) latest = scopeId;
  return latest;
}

function nowMs(): number {
  return Date.now();
}
