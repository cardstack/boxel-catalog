import Component from '@glimmer/component';
import { guidFor } from '@ember/object/internals';
import { cached, tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import type Owner from '@ember/owner';
import { modifier } from 'ember-modifier';
import { consume, provide } from 'ember-provide-consume-context';
import ContextProvider from 'ember-provide-consume-context/components/context-provider';

import { createFocusLadder } from '../focus-ladder.ts';
import type {
  FocusLadder,
  LadderSurface,
  Target,
  TargetScope,
} from '../focus-ladder.ts';
export type { Target } from '../focus-ladder.ts';
import type {
  FociEditPolicy,
  FociGridCoordinate,
  FociKeyboardPolicy,
  FociMovementPolicy,
  FociNodePolicy,
  FociPointerPolicy,
  FociPreset,
  FociPresetAspect,
  FociSelectionPolicy,
  FociTraversalModel,
  FociTraversalPolicy,
} from '../foci-store.ts';
export type { FociNodePolicy } from '../foci-store.ts';
import {
  createSurfaceRuntime,
  type SurfaceRuntime,
} from '../surface-runtime.ts';
import {
  createSurfaceScopeRelay,
  SurfaceScopeContextName,
  type SurfaceScopeRelay,
} from '../scope-relay.ts';
import surfaceNode from '../modifiers/node.ts';
import surfaceRoot from '../modifiers/root.ts';
import surfaceInlineEdit from '../modifiers/inline-edit.ts';
import type { InlineEditOptions } from '../modifiers/inline-edit.ts';
import surfaceScopeRelay from '../modifiers/scope-relay.ts';
import surfaceCoordinateDebugger from '../modifiers/coordinate-debugger.ts';
import type { CoordinateDebugView } from '../modifiers/coordinate-debugger.ts';
import Lift from './lift.gts';
import {
  LadderContextName,
  SurfaceRuntimeContextName,
  ParentIdContextName,
  ParentContextName,
  DemoContextName,
  ModeContextName,
  InspectContextName,
  PathContextName,
  ChangeRouteContextName,
  CoordinateSpaceContextName,
} from '../surface-contexts.ts';
export {
  LadderContextName,
  SurfaceRuntimeContextName,
  ParentIdContextName,
  ParentContextName,
  DemoContextName,
  ModeContextName,
  InspectContextName,
  PathContextName,
  ChangeRouteContextName,
  CoordinateSpaceContextName,
} from '../surface-contexts.ts';
import { createLiftManager, LiftContextName } from '../lift-edges.ts';
import type {
  SurfaceLiftEdgeInput,
  LiftEdges,
  LiftManager,
  LiftResolver,
  LiftTargetComponent,
  LiftTargetContext,
} from '../lift-edges.ts';
import {
  FormFieldContextName,
  type FormFieldContext,
} from '../form-field-context.ts';

type SurfaceTag = 'article' | 'aside' | 'button' | 'div' | 'nav' | 'section';

export type DemoMode = boolean | string;
export type KeyboardMode = boolean | 'surface-tree' | 'manual' | 'none';
export type Mode = 'use' | 'change' | 'inspect';
export type Posture = 'use' | 'compose';
export type ChangeRoute = 'auto' | 'inline' | 'lifted';
export type Role = 'content' | 'structure' | 'control';
export type DirectiveScope = 'self' | 'children' | 'descendants' | 'subtree';
export type CellSurface = 'form' | 'grid' | 'canvas' | 'scene';
export type CellValidationState =
  | 'none'
  | 'valid'
  | 'invalid'
  | 'loading'
  | 'initial';
export type CellState =
  | 'idle'
  | 'hovered'
  | 'active'
  | 'editing-inline'
  | 'lift-host'
  | 'drag-source'
  | 'drop-target';
export type SurfaceCoordinateSource =
  | 'explicit'
  | 'identity'
  | 'context'
  | 'generated';
export type Identity =
  | string
  | number
  | { id: string | number }
  | { '@id': string | number };
export type IdentityPart = string | number | boolean;
export type Path = IdentityPart[];
export type CoordinateSpace = string;
export type LocalCoordinate =
  | string
  | number
  | boolean
  | null
  | Record<string, unknown>
  | unknown[];

export interface CoordinateSpaceContext {
  surface: LadderSurface;
  id: string;
  schema: CoordinateSpace;
}

function defaultCoordinateSpaceSchema(surface: LadderSurface): CoordinateSpace {
  switch (surface) {
    case 'space':
      return 'surface-network';
    case 'layout':
      return 'layout';
    case 'canvas':
      return 'canvas-plane';
    case 'scene':
      return 'scene-world';
    case 'grid':
      return 'range-grid';
    case 'row':
      return 'range-row';
    case 'scroll':
      return 'document-flow';
    case 'flow':
      return 'ordered-list';
    case 'outline':
      return 'outline-tree';
    case 'connection':
      return 'connection-path';
    case 'frame':
      return 'fitted-rect';
    case 'pane':
      return 'pane-slot';
    case 'plane':
      return 'plane-layer';
    case 'cell':
      return 'cell-value';
    case 'run':
      return 'text';
    case 'unit':
      return 'token';
  }
}

export interface ChangePreference {
  inline?: boolean | InlineEditOptions;
  lift?: false | SurfaceLiftEdgeInput;
}

export type ChangeInput = boolean | ChangePreference;

let counters: Record<string, number> = {};

export function nextSurfaceId(surface: string): string {
  counters[surface] = (counters[surface] ?? 0) + 1;
  return `${surface}:${counters[surface]}`;
}

export function nextScopedSurfaceId(
  parentId: string | undefined,
  surface: string,
): string {
  if (!parentId) return nextSurfaceId(surface);
  const key = `${parentId}/${surface}`;
  counters[key] = (counters[key] ?? 0) + 1;
  return `${parentId}/${surface}:${counters[key]}`;
}

function identityValue(identity: Identity): string | number {
  if (typeof identity === 'object') {
    if ('id' in identity) {
      return identity.id;
    }

    return identity['@id'];
  }

  return identity;
}

function coordinatePartAttribute(value: unknown): string | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }

  if (
    typeof value === 'string' ||
    typeof value === 'number' ||
    typeof value === 'boolean'
  ) {
    return String(value);
  }

  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

function encodeIdPart(part: IdentityPart): string {
  return encodeURIComponent(String(part));
}

export function surfaceId(
  surface: string,
  identity: Identity,
  ...parts: IdentityPart[]
): string {
  return [
    surface,
    encodeIdPart(identityValue(identity)),
    ...parts.map(encodeIdPart),
  ].join(':');
}

export function surfaceFocusKey(
  identity: Identity,
  ...parts: IdentityPart[]
): string {
  return [
    encodeIdPart(identityValue(identity)),
    ...parts.map(encodeIdPart),
  ].join(':');
}

export function surfaceIdFromPath(surface: string, path: Path): string {
  return [surface, ...path.map(encodeIdPart)].join(':');
}

export function surfaceFocusKeyFromPath(path: Path): string {
  return path.map(encodeIdPart).join(':');
}

function normalizeSurfacePath(identity: Identity, parts: IdentityPart[]): Path {
  return [identityValue(identity), ...parts];
}

function normalizeChange(
  change: ChangeInput | undefined,
): ChangePreference | undefined {
  if (!change) return undefined;
  return change === true ? {} : change;
}

function modeForPosture(posture: Posture | undefined): Mode | undefined {
  if (posture === undefined) return undefined;
  return posture === 'compose' ? 'change' : 'use';
}

function inlineOptions(
  change: ChangePreference | undefined,
): InlineEditOptions | undefined {
  if (!change?.inline) return undefined;
  return change.inline === true ? {} : change.inline;
}

function liftEdgesWithChange(
  base: LiftEdges | undefined,
  change: ChangePreference | undefined,
  useChangeLift: boolean,
): LiftEdges | undefined {
  if (!useChangeLift || !change || change.lift === false) return base;
  return {
    ...(base ?? {}),
    edit: change.lift ?? true,
  };
}

export interface SurfaceComponentSignature {
  Args: {
    id?: string;
    focusKey?: string;
    surfacePath?: Path;
    /** Presentation/interaction coordinate-space id. This is not the persistent record. */
    space?: Identity;
    /** Reserved for CardDef/FieldDef integration. Ignored by the Surface runtime. */
    model?: unknown;
    /** Reserved for CardDef/FieldDef integration. Ignored by the Surface runtime. */
    field?: unknown;
    /** Reserved for CardDef/FieldDef integration. Ignored by the Surface runtime. */
    fields?: unknown;
    /** Optional coordinate-space schema when the surface default is not specific enough. */
    schema?: CoordinateSpace;
    /** Local coordinate inside the nearest parent coordinate space. */
    coord?: LocalCoordinate;
    /** Compatibility alias for @space. Prefer @space in V3 authoring. */
    identity?: Identity;
    key?: IdentityPart | IdentityPart[];
    identityPart?: IdentityPart | IdentityPart[];
    tag?: SurfaceTag;
    inline?: boolean;
    role?: Role;
    /** Cell chrome surface override. Used by Cell only. */
    surface?: CellSurface;
    /** Cell validation state. Used by Cell only. */
    state?: CellValidationState;
    disabled?: boolean;
    readonly?: boolean;
    bottomTreatment?: 'flat' | 'rounded';
    chained?: boolean;
    pattern?: string;
    /** Runtime preset. Package wrappers should pass their behavior preset here. */
    preset?: FociPreset;
    /** Extra preset aspects for the runtime compiler. */
    aspects?: FociPresetAspect[];
    /** Full low-level runtime policy escape hatch. Prefer preset/aspects first. */
    runtimePolicy?: FociNodePolicy;
    /** Optional grid coordinate used by engine-owned sheet movement/ranges. */
    grid?: FociGridCoordinate;
    gridRow?: number;
    gridCol?: number;
    runtimeTraversal?: FociTraversalPolicy;
    runtimeTraversalModel?: FociTraversalModel;
    runtimeSelection?: FociSelectionPolicy;
    runtimeKeyboard?: FociKeyboardPolicy;
    runtimeMovement?: FociMovementPolicy;
    runtimePointer?: FociPointerPolicy;
    runtimeEdit?: FociEditPolicy;
    accepts?: string[];
    payloadType?: string;
    scope?: DirectiveScope;
    depth?: number | 'all';
    expanded?: boolean;
    onSelect?: (event: Event) => void;
    onActivate?: (event: Event) => void;
    scrollOnSelect?: boolean;
    scrollTarget?: string;
    scrollAnchor?: string;
    hoverSignal?: string;
    hoverAnchor?: string;
    onExpand?: (event: Event) => void;
    onCollapse?: (event: Event) => void;
    demo?: DemoMode;
    /** V3 authoring posture. Prefer this over @mode for use/compose surfaces. */
    posture?: Posture;
    /** Low-level runtime mode. Kept for compatibility; prefer @posture plus @inspect in V3. */
    mode?: Mode;
    /** Inspection overlay. Independent from use/change posture. Defaults true when @mode='inspect'. */
    inspect?: boolean;
    changeRoute?: ChangeRoute;
    target?: Target;
    targetScope?: TargetScope;
    /** Compatibility alias for @schema. Prefer @space plus optional @schema in V3 authoring. */
    coordinateSpace?: CoordinateSpace;
    /** Compatibility alias for @coord. Prefer @coord in V3 authoring. */
    at?: LocalCoordinate;
    change?: ChangeInput;
    lift?: LiftEdges;
    liftData?: unknown;
    inlineEdit?: boolean;
    editValue?: string;
    editLabel?: string;
    editMultiline?: boolean;
    onEditInput?: (value: string, event: InputEvent) => void;
  };
  Blocks: {
    default: [];
    pre: [];
    post: [];
  };
  Element: HTMLElement;
}

export abstract class SurfaceComponent extends Component<SurfaceComponentSignature> {
  private generatedId: string | undefined;

  @consume(LadderContextName) declare inheritedLadder: FocusLadder | undefined;
  @consume(SurfaceRuntimeContextName) declare inheritedSurfaceRuntime:
    | SurfaceRuntime
    | undefined;
  @consume(ParentIdContextName) declare inheritedParentId: string | undefined;
  @consume(ParentContextName) declare inheritedParentSurface:
    | LadderSurface
    | undefined;
  @consume(DemoContextName) declare inheritedDemo: DemoMode | undefined;
  @consume(ModeContextName) declare inheritedMode: Mode | undefined;
  @consume(InspectContextName) declare inheritedInspect: boolean | undefined;
  @consume(ChangeRouteContextName) declare inheritedChangeRoute:
    | ChangeRoute
    | undefined;
  @consume(PathContextName) declare inheritedSurfacePath: Path | undefined;
  @consume(CoordinateSpaceContextName) declare inheritedCoordinateSpace:
    | CoordinateSpaceContext
    | undefined;
  @consume(LiftContextName) declare inheritedLiftManager:
    | LiftManager
    | undefined;
  @consume(SurfaceScopeContextName) declare inheritedScopeRelay:
    | SurfaceScopeRelay
    | undefined;

  private localScopeRelay: SurfaceScopeRelay | undefined;

  abstract get surface(): LadderSurface;

  get scopeRelay(): SurfaceScopeRelay {
    let relay = this.localScopeRelay;
    if (!relay || relay.parent !== this.inheritedScopeRelay) {
      relay = createSurfaceScopeRelay(this.inheritedScopeRelay);
      // eslint-disable-next-line ember/no-side-effects
      this.localScopeRelay = relay;
    }
    return relay;
  }

  get spaceIdentity(): Identity | undefined {
    return this.args.space ?? this.args.identity;
  }

  get localCoordinate(): LocalCoordinate | undefined {
    return this.args.coord ?? this.args.at;
  }

  @cached
  get coordinateSchema(): CoordinateSpace | undefined {
    return (
      this.args.schema ??
      this.args.coordinateSpace ??
      (this.spaceIdentity !== undefined
        ? defaultCoordinateSpaceSchema(this.surface)
        : undefined)
    );
  }

  @cached
  get id(): string {
    if (this.args.id) {
      return this.args.id;
    }

    if (this.usesAnonymousLeafGeneratedId) {
      // eslint-disable-next-line ember/no-side-effects
      this.generatedId ??= nextScopedSurfaceId(
        this.inheritedParentId,
        this.surface,
      );
      return this.generatedId;
    }

    if (this.surfacePath !== undefined && !this.usesContextScopedGeneratedId) {
      return surfaceIdFromPath(this.surface, this.surfacePath);
    }

    if (this.spaceIdentity !== undefined) {
      return surfaceId(this.surface, this.spaceIdentity, ...this.keyParts);
    }

    // eslint-disable-next-line ember/no-side-effects
    this.generatedId ??= this.usesContextScopedGeneratedId
      ? nextScopedSurfaceId(this.inheritedParentId, this.surface)
      : nextSurfaceId(this.surface);
    return this.generatedId;
  }

  @cached
  get focusKey(): string | undefined {
    if (this.args.focusKey) {
      return this.args.focusKey;
    }

    if (this.surfacePath !== undefined) {
      return surfaceFocusKeyFromPath(this.surfacePath);
    }

    if (this.spaceIdentity !== undefined) {
      return surfaceFocusKey(this.spaceIdentity, ...this.keyParts);
    }

    return undefined;
  }

  get pathAttribute(): string | undefined {
    return this.surfacePath !== undefined
      ? surfaceFocusKeyFromPath(this.surfacePath)
      : undefined;
  }

  @cached
  get coordinate(): string | undefined {
    if (
      this.args.coord !== undefined &&
      this.inheritedCoordinateSpace !== undefined
    ) {
      let local = coordinatePartAttribute(this.args.coord);
      return local !== undefined
        ? `${this.inheritedCoordinateSpace.id}[${this.inheritedCoordinateSpace.schema}]:${local}`
        : `${this.inheritedCoordinateSpace.id}[${this.inheritedCoordinateSpace.schema}]`;
    }

    if (this.coordinateSchema !== undefined) {
      let local = coordinatePartAttribute(this.localCoordinate);
      let spaceId = this.coordinateSpaceId;
      return local !== undefined
        ? `${spaceId}[${this.coordinateSchema}]:${local}`
        : `${spaceId}[${this.coordinateSchema}]`;
    }

    if (
      this.localCoordinate !== undefined &&
      this.inheritedCoordinateSpace !== undefined
    ) {
      let local = coordinatePartAttribute(this.localCoordinate);
      return local !== undefined
        ? `${this.inheritedCoordinateSpace.id}[${this.inheritedCoordinateSpace.schema}]:${local}`
        : `${this.inheritedCoordinateSpace.id}[${this.inheritedCoordinateSpace.schema}]`;
    }

    return this.pathAttribute ?? this.args.focusKey;
  }

  get coordinateSpaceAttribute(): string | undefined {
    if (this.coordinateSchema !== undefined) {
      return this.coordinateSchema;
    }

    if (this.localCoordinate !== undefined) {
      return this.inheritedCoordinateSpace?.schema;
    }

    return undefined;
  }

  get localCoordinateAttribute(): string | undefined {
    return coordinatePartAttribute(this.localCoordinate);
  }

  get directiveDepthAttribute(): string | undefined {
    return this.args.depth === undefined ? undefined : String(this.args.depth);
  }

  get expandableAttribute(): string | undefined {
    return this.args.expanded === undefined ? undefined : 'true';
  }

  get expandedAttribute(): string | undefined {
    return this.args.expanded === undefined
      ? undefined
      : String(this.args.expanded);
  }

  @cached
  get coordinateSpaceId(): string {
    if (
      this.coordinateSchema === undefined &&
      this.localCoordinate !== undefined &&
      this.inheritedCoordinateSpace !== undefined
    ) {
      return this.inheritedCoordinateSpace.id;
    }

    return this.focusKey ?? this.id;
  }

  get providedCoordinateSpace(): CoordinateSpaceContext | undefined {
    if (this.coordinateSchema !== undefined) {
      return {
        surface: this.surface,
        id: this.focusKey ?? this.id,
        schema: this.coordinateSchema,
      };
    }

    return this.inheritedCoordinateSpace;
  }

  get coordinateSource(): SurfaceCoordinateSource {
    if (
      this.args.surfacePath !== undefined ||
      this.args.focusKey !== undefined ||
      this.args.id !== undefined ||
      this.args.space !== undefined ||
      this.args.schema !== undefined ||
      this.args.coord !== undefined ||
      this.args.coordinateSpace !== undefined ||
      this.args.at !== undefined
    ) {
      return 'explicit';
    }

    if (this.spaceIdentity !== undefined) {
      return 'identity';
    }

    if (this.inheritedSurfacePath !== undefined) {
      return 'context';
    }

    return 'generated';
  }

  get usesGeneratedId(): boolean {
    return (
      this.usesAnonymousLeafGeneratedId ||
      this.usesContextScopedGeneratedId ||
      (this.args.id === undefined &&
        this.spaceIdentity === undefined &&
        this.surfacePath === undefined)
    );
  }

  get usesAnonymousLeafGeneratedId(): boolean {
    return (
      this.args.id === undefined &&
      (this.surface === 'run' || this.surface === 'unit')
    );
  }

  get usesContextScopedGeneratedId(): boolean {
    return (
      this.args.id === undefined &&
      this.args.surfacePath === undefined &&
      this.spaceIdentity === undefined &&
      this.keyParts.length === 0 &&
      this.inheritedSurfacePath !== undefined
    );
  }

  get keyParts(): IdentityPart[] {
    if (Array.isArray(this.args.key)) {
      return this.args.key;
    }

    if (this.args.key !== undefined) {
      return [this.args.key];
    }

    if (Array.isArray(this.args.identityPart)) {
      return this.args.identityPart;
    }

    if (this.args.identityPart !== undefined) {
      return [this.args.identityPart];
    }

    return [];
  }

  get surfacePath(): Path | undefined {
    if (this.args.surfacePath !== undefined) {
      return this.args.surfacePath;
    }

    if (this.spaceIdentity !== undefined) {
      return normalizeSurfacePath(this.spaceIdentity, this.keyParts);
    }

    if (this.inheritedSurfacePath !== undefined) {
      return [...this.inheritedSurfacePath, ...this.keyParts];
    }

    return undefined;
  }

  get ladder(): FocusLadder | undefined {
    return this.inheritedLadder;
  }

  get runtime(): SurfaceRuntime | undefined {
    return this.inheritedSurfaceRuntime;
  }

  @cached
  get runtimeGridCoordinate(): FociGridCoordinate | undefined {
    if (this.args.grid) return this.args.grid;
    if (this.args.gridRow === undefined || this.args.gridCol === undefined) {
      return undefined;
    }
    return {
      row: this.args.gridRow,
      col: this.args.gridCol,
    };
  }

  @cached
  get runtimePolicy(): FociNodePolicy | undefined {
    const policy: FociNodePolicy = {
      ...(this.args.runtimePolicy ?? {}),
    };
    if (this.args.preset !== undefined) policy.preset = this.args.preset;
    if (this.args.aspects !== undefined) policy.aspects = this.args.aspects;
    if (this.args.runtimeTraversal !== undefined) {
      policy.traversal = this.args.runtimeTraversal;
    }
    if (this.args.runtimeTraversalModel !== undefined) {
      policy.traversalModel = this.args.runtimeTraversalModel;
    }
    if (this.args.runtimeSelection !== undefined) {
      policy.selection = this.args.runtimeSelection;
    }
    if (this.args.runtimeKeyboard !== undefined) {
      policy.keyboard = this.args.runtimeKeyboard;
    }
    if (this.args.runtimeMovement !== undefined) {
      policy.movement = this.args.runtimeMovement;
    }
    if (this.args.runtimePointer !== undefined) {
      policy.pointer = this.args.runtimePointer;
    }
    if (this.args.runtimeEdit !== undefined) {
      policy.edit = this.args.runtimeEdit;
    } else if (this.changeUsesInline) {
      policy.edit = 'inline';
    } else if (this.changeUsesLift) {
      policy.edit = 'lifted';
    }
    if (this.args.accepts !== undefined) policy.accepts = this.args.accepts;
    if (this.args.payloadType !== undefined) {
      policy.payloadType = this.args.payloadType;
    }

    return Object.keys(policy).length > 0 ? policy : undefined;
  }

  get parentId(): string | undefined {
    return this.inheritedParentId;
  }

  get demo(): DemoMode {
    return this.args.demo ?? this.inheritedDemo ?? false;
  }

  get mode(): Mode {
    return (
      this.args.mode ??
      modeForPosture(this.args.posture) ??
      this.inheritedMode ??
      'use'
    );
  }

  get explicitModeAttribute(): Mode | undefined {
    return this.args.mode ?? modeForPosture(this.args.posture);
  }

  get inspect(): boolean {
    return (
      this.args.inspect ?? this.inheritedInspect ?? this.mode === 'inspect'
    );
  }

  get inspectAttribute(): string {
    return String(this.inspect);
  }

  get explicitInspectAttribute(): string | undefined {
    return this.args.inspect === undefined
      ? undefined
      : String(this.args.inspect);
  }

  get changeRoute(): ChangeRoute {
    return this.args.changeRoute ?? this.inheritedChangeRoute ?? 'auto';
  }

  get tag(): SurfaceTag {
    return this.args.tag ?? 'div';
  }

  get inline(): boolean {
    return this.args.inline ?? false;
  }

  get liftManager(): LiftManager | undefined {
    return this.inheritedLiftManager;
  }

  get activeLiftSourceId(): string | undefined {
    return this.liftManager?.activeSourceId;
  }

  get activeLiftTargetId(): string | undefined {
    return this.liftManager?.activeTargetId;
  }

  get activeLiftKind(): string | undefined {
    return this.liftManager?.kind;
  }

  get activeLiftFocusToken(): number | undefined {
    return this.liftManager?.focusToken;
  }

  get changePreference(): ChangePreference | undefined {
    return normalizeChange(this.args.change);
  }

  get changeInlineOptions(): InlineEditOptions | undefined {
    return inlineOptions(this.changePreference);
  }

  get changeUsesInline(): boolean {
    return this.changeInlineOptions !== undefined;
  }

  get changeUsesLift(): boolean {
    return this.changePreference !== undefined;
  }

  get liftEdges(): LiftEdges | undefined {
    return liftEdgesWithChange(
      this.args.lift,
      this.changePreference,
      this.changeUsesLift,
    );
  }

  get inlineEditEnabled(): boolean {
    return this.args.inlineEdit ?? this.changeUsesInline;
  }

  get inlineEditActivation(): 'always' | 'change-inline' {
    return this.args.inlineEdit === undefined && this.changeUsesInline
      ? 'change-inline'
      : 'always';
  }

  get inlineEditValue(): string | undefined {
    return this.changeInlineOptions?.value ?? this.args.editValue;
  }

  get inlineEditLabel(): string | undefined {
    return this.changeInlineOptions?.label ?? this.args.editLabel;
  }

  get inlineEditMultiline(): boolean | undefined {
    return this.changeInlineOptions?.multiline ?? this.args.editMultiline;
  }

  get inlineEditInput():
    | ((value: string, event: InputEvent) => void)
    | undefined {
    return this.changeInlineOptions?.onInput ?? this.args.onEditInput;
  }

  @provide(ParentIdContextName)
  get providedParentId(): string {
    return this.id;
  }

  @provide(ParentContextName)
  get providedParentSurface(): LadderSurface {
    return this.surface;
  }

  @provide(DemoContextName)
  get providedDemo(): DemoMode {
    return this.demo;
  }

  @provide(ModeContextName)
  get providedMode(): Mode {
    return this.mode;
  }

  @provide(InspectContextName)
  get providedInspect(): boolean {
    return this.inspect;
  }

  @provide(ChangeRouteContextName)
  get providedChangeRoute(): ChangeRoute {
    return this.changeRoute;
  }

  @provide(PathContextName)
  get providedSurfacePath(): Path | undefined {
    return this.surfacePath;
  }

  @provide(CoordinateSpaceContextName)
  get providedCoordinateSpaceContext(): CoordinateSpaceContext | undefined {
    return this.providedCoordinateSpace;
  }

  @provide(SurfaceScopeContextName)
  get providedScopeRelay(): SurfaceScopeRelay {
    return this.scopeRelay;
  }

  get isArticle(): boolean {
    return this.tag === 'article';
  }

  get isAside(): boolean {
    return this.tag === 'aside';
  }

  get isNav(): boolean {
    return this.tag === 'nav';
  }

  get isButton(): boolean {
    return this.tag === 'button';
  }

  get isSection(): boolean {
    return this.tag === 'section';
  }

  <template>
    <ContextProvider @key={{ParentIdContextName}} @value={{this.id}}>
      <ContextProvider @key={{ParentContextName}} @value={{this.surface}}>
        <ContextProvider @key={{DemoContextName}} @value={{this.demo}}>
          <ContextProvider @key={{ModeContextName}} @value={{this.mode}}>
            <ContextProvider
              @key={{InspectContextName}}
              @value={{this.inspect}}
            >
              <ContextProvider
                @key={{ChangeRouteContextName}}
                @value={{this.changeRoute}}
              >
                <ContextProvider
                  @key={{PathContextName}}
                  @value={{this.surfacePath}}
                >
                  <ContextProvider
                    @key={{CoordinateSpaceContextName}}
                    @value={{this.providedCoordinateSpace}}
                  >
                    <ContextProvider
                      @key={{SurfaceScopeContextName}}
                      @value={{this.scopeRelay}}
                    >
                      {{#if this.isArticle}}
                        <article
                          id={{this.id}}
                          data-surface-component={{this.surface}}
                          data-surface-role={{this.args.role}}
                          data-surface-pattern={{this.args.pattern}}
                          data-surface-scope={{this.args.scope}}
                          data-surface-depth={{this.directiveDepthAttribute}}
                          data-surface-expandable={{this.expandableAttribute}}
                          data-surface-expanded={{this.expandedAttribute}}
                          data-surface-mode={{this.explicitModeAttribute}}
                          data-surface-posture={{this.args.posture}}
                          data-surface-inspect={{this.explicitInspectAttribute}}
                          data-surface-change-route={{this.args.changeRoute}}
                          data-surface-target={{this.args.target}}
                          data-surface-target-scope={{this.args.targetScope}}
                          data-surface-coordinate-space={{this.coordinateSpaceAttribute}}
                          data-surface-coordinate-space-id={{this.coordinateSpaceId}}
                          data-surface-local-coordinate={{this.localCoordinateAttribute}}
                          data-surface-focus-key={{this.focusKey}}
                          data-surface-path={{this.pathAttribute}}
                          data-surface-coordinate={{this.coordinate}}
                          {{surfaceNode
                            this.ladder
                            runtime=this.runtime
                            id=this.id
                            surface=this.surface
                            parentId=this.parentId
                            mode=this.explicitModeAttribute
                            target=this.args.target
                            targetScope=this.args.targetScope
                            focusKey=this.focusKey
                            coordinate=this.coordinate
                            coordinateSpace=this.coordinateSpaceAttribute
                            localCoordinate=this.localCoordinateAttribute
                            coordinateSource=this.coordinateSource
                            keyParts=this.keyParts
                            generatedId=this.usesGeneratedId
                            policy=this.runtimePolicy
                            grid=this.runtimeGridCoordinate
                            expanded=this.args.expanded
                            onSelect=this.args.onSelect
                            onActivate=this.args.onActivate
                            scrollOnSelect=this.args.scrollOnSelect
                            scrollTarget=this.args.scrollTarget
                            scrollAnchor=this.args.scrollAnchor
                            hoverSignal=this.args.hoverSignal
                            hoverAnchor=this.args.hoverAnchor
                            onExpand=this.args.onExpand
                            onCollapse=this.args.onCollapse
                            lift=this.liftEdges
                            liftData=this.args.liftData
                            liftManager=this.liftManager
                            liftActiveSourceId=this.activeLiftSourceId
                            liftActiveTargetId=this.activeLiftTargetId
                            liftActiveKind=this.activeLiftKind
                          }}
                          {{surfaceScopeRelay this.scopeRelay}}
                          {{surfaceInlineEdit
                            enabled=this.inlineEditEnabled
                            activation=this.inlineEditActivation
                            value=this.inlineEditValue
                            label=this.inlineEditLabel
                            multiline=this.inlineEditMultiline
                            onInput=this.inlineEditInput
                          }}
                          ...attributes
                        >
                          {{yield}}
                        </article>
                      {{else if this.isAside}}
                        <aside
                          id={{this.id}}
                          data-surface-component={{this.surface}}
                          data-surface-role={{this.args.role}}
                          data-surface-pattern={{this.args.pattern}}
                          data-surface-scope={{this.args.scope}}
                          data-surface-depth={{this.directiveDepthAttribute}}
                          data-surface-expandable={{this.expandableAttribute}}
                          data-surface-expanded={{this.expandedAttribute}}
                          data-surface-mode={{this.explicitModeAttribute}}
                          data-surface-posture={{this.args.posture}}
                          data-surface-inspect={{this.explicitInspectAttribute}}
                          data-surface-change-route={{this.args.changeRoute}}
                          data-surface-target={{this.args.target}}
                          data-surface-target-scope={{this.args.targetScope}}
                          data-surface-coordinate-space={{this.coordinateSpaceAttribute}}
                          data-surface-coordinate-space-id={{this.coordinateSpaceId}}
                          data-surface-local-coordinate={{this.localCoordinateAttribute}}
                          data-surface-focus-key={{this.focusKey}}
                          data-surface-path={{this.pathAttribute}}
                          data-surface-coordinate={{this.coordinate}}
                          {{surfaceNode
                            this.ladder
                            runtime=this.runtime
                            id=this.id
                            surface=this.surface
                            parentId=this.parentId
                            mode=this.explicitModeAttribute
                            target=this.args.target
                            targetScope=this.args.targetScope
                            focusKey=this.focusKey
                            coordinate=this.coordinate
                            coordinateSpace=this.coordinateSpaceAttribute
                            localCoordinate=this.localCoordinateAttribute
                            coordinateSource=this.coordinateSource
                            keyParts=this.keyParts
                            generatedId=this.usesGeneratedId
                            policy=this.runtimePolicy
                            grid=this.runtimeGridCoordinate
                            expanded=this.args.expanded
                            onSelect=this.args.onSelect
                            onActivate=this.args.onActivate
                            scrollOnSelect=this.args.scrollOnSelect
                            scrollTarget=this.args.scrollTarget
                            scrollAnchor=this.args.scrollAnchor
                            hoverSignal=this.args.hoverSignal
                            hoverAnchor=this.args.hoverAnchor
                            onExpand=this.args.onExpand
                            onCollapse=this.args.onCollapse
                            lift=this.liftEdges
                            liftData=this.args.liftData
                            liftManager=this.liftManager
                            liftActiveSourceId=this.activeLiftSourceId
                            liftActiveTargetId=this.activeLiftTargetId
                            liftActiveKind=this.activeLiftKind
                          }}
                          {{surfaceScopeRelay this.scopeRelay}}
                          {{surfaceInlineEdit
                            enabled=this.inlineEditEnabled
                            activation=this.inlineEditActivation
                            value=this.inlineEditValue
                            label=this.inlineEditLabel
                            multiline=this.inlineEditMultiline
                            onInput=this.inlineEditInput
                          }}
                          ...attributes
                        >
                          {{yield}}
                        </aside>
                      {{else if this.isNav}}
                        <nav
                          id={{this.id}}
                          data-surface-component={{this.surface}}
                          data-surface-role={{this.args.role}}
                          data-surface-pattern={{this.args.pattern}}
                          data-surface-scope={{this.args.scope}}
                          data-surface-depth={{this.directiveDepthAttribute}}
                          data-surface-expandable={{this.expandableAttribute}}
                          data-surface-expanded={{this.expandedAttribute}}
                          data-surface-mode={{this.explicitModeAttribute}}
                          data-surface-posture={{this.args.posture}}
                          data-surface-inspect={{this.explicitInspectAttribute}}
                          data-surface-change-route={{this.args.changeRoute}}
                          data-surface-target={{this.args.target}}
                          data-surface-target-scope={{this.args.targetScope}}
                          data-surface-coordinate-space={{this.coordinateSpaceAttribute}}
                          data-surface-coordinate-space-id={{this.coordinateSpaceId}}
                          data-surface-local-coordinate={{this.localCoordinateAttribute}}
                          data-surface-focus-key={{this.focusKey}}
                          data-surface-path={{this.pathAttribute}}
                          data-surface-coordinate={{this.coordinate}}
                          {{surfaceNode
                            this.ladder
                            runtime=this.runtime
                            id=this.id
                            surface=this.surface
                            parentId=this.parentId
                            mode=this.explicitModeAttribute
                            target=this.args.target
                            targetScope=this.args.targetScope
                            focusKey=this.focusKey
                            coordinate=this.coordinate
                            coordinateSpace=this.coordinateSpaceAttribute
                            localCoordinate=this.localCoordinateAttribute
                            coordinateSource=this.coordinateSource
                            keyParts=this.keyParts
                            generatedId=this.usesGeneratedId
                            policy=this.runtimePolicy
                            grid=this.runtimeGridCoordinate
                            expanded=this.args.expanded
                            onSelect=this.args.onSelect
                            onActivate=this.args.onActivate
                            scrollOnSelect=this.args.scrollOnSelect
                            scrollTarget=this.args.scrollTarget
                            scrollAnchor=this.args.scrollAnchor
                            hoverSignal=this.args.hoverSignal
                            hoverAnchor=this.args.hoverAnchor
                            onExpand=this.args.onExpand
                            onCollapse=this.args.onCollapse
                            lift=this.liftEdges
                            liftData=this.args.liftData
                            liftManager=this.liftManager
                            liftActiveSourceId=this.activeLiftSourceId
                            liftActiveTargetId=this.activeLiftTargetId
                            liftActiveKind=this.activeLiftKind
                          }}
                          {{surfaceScopeRelay this.scopeRelay}}
                          {{surfaceInlineEdit
                            enabled=this.inlineEditEnabled
                            activation=this.inlineEditActivation
                            value=this.inlineEditValue
                            label=this.inlineEditLabel
                            multiline=this.inlineEditMultiline
                            onInput=this.inlineEditInput
                          }}
                          ...attributes
                        >
                          {{yield}}
                        </nav>
                      {{else if this.isButton}}
                        <button
                          id={{this.id}}
                          data-surface-component={{this.surface}}
                          data-surface-role={{this.args.role}}
                          data-surface-pattern={{this.args.pattern}}
                          data-surface-scope={{this.args.scope}}
                          data-surface-depth={{this.directiveDepthAttribute}}
                          data-surface-expandable={{this.expandableAttribute}}
                          data-surface-expanded={{this.expandedAttribute}}
                          data-surface-mode={{this.explicitModeAttribute}}
                          data-surface-posture={{this.args.posture}}
                          data-surface-inspect={{this.explicitInspectAttribute}}
                          data-surface-change-route={{this.args.changeRoute}}
                          data-surface-target={{this.args.target}}
                          data-surface-target-scope={{this.args.targetScope}}
                          data-surface-coordinate-space={{this.coordinateSpaceAttribute}}
                          data-surface-coordinate-space-id={{this.coordinateSpaceId}}
                          data-surface-local-coordinate={{this.localCoordinateAttribute}}
                          data-surface-focus-key={{this.focusKey}}
                          data-surface-path={{this.pathAttribute}}
                          data-surface-coordinate={{this.coordinate}}
                          {{surfaceNode
                            this.ladder
                            runtime=this.runtime
                            id=this.id
                            surface=this.surface
                            parentId=this.parentId
                            mode=this.explicitModeAttribute
                            target=this.args.target
                            targetScope=this.args.targetScope
                            focusKey=this.focusKey
                            coordinate=this.coordinate
                            coordinateSpace=this.coordinateSpaceAttribute
                            localCoordinate=this.localCoordinateAttribute
                            coordinateSource=this.coordinateSource
                            keyParts=this.keyParts
                            generatedId=this.usesGeneratedId
                            policy=this.runtimePolicy
                            grid=this.runtimeGridCoordinate
                            expanded=this.args.expanded
                            onSelect=this.args.onSelect
                            onActivate=this.args.onActivate
                            scrollOnSelect=this.args.scrollOnSelect
                            scrollTarget=this.args.scrollTarget
                            scrollAnchor=this.args.scrollAnchor
                            hoverSignal=this.args.hoverSignal
                            hoverAnchor=this.args.hoverAnchor
                            onExpand=this.args.onExpand
                            onCollapse=this.args.onCollapse
                            lift=this.liftEdges
                            liftData=this.args.liftData
                            liftManager=this.liftManager
                            liftActiveSourceId=this.activeLiftSourceId
                            liftActiveTargetId=this.activeLiftTargetId
                            liftActiveKind=this.activeLiftKind
                          }}
                          {{surfaceScopeRelay this.scopeRelay}}
                          {{surfaceInlineEdit
                            enabled=this.inlineEditEnabled
                            activation=this.inlineEditActivation
                            value=this.inlineEditValue
                            label=this.inlineEditLabel
                            multiline=this.inlineEditMultiline
                            onInput=this.inlineEditInput
                          }}
                          ...attributes
                        >
                          {{yield}}
                        </button>
                      {{else if this.isSection}}
                        <section
                          id={{this.id}}
                          data-surface-component={{this.surface}}
                          data-surface-role={{this.args.role}}
                          data-surface-pattern={{this.args.pattern}}
                          data-surface-scope={{this.args.scope}}
                          data-surface-depth={{this.directiveDepthAttribute}}
                          data-surface-expandable={{this.expandableAttribute}}
                          data-surface-expanded={{this.expandedAttribute}}
                          data-surface-mode={{this.explicitModeAttribute}}
                          data-surface-posture={{this.args.posture}}
                          data-surface-inspect={{this.explicitInspectAttribute}}
                          data-surface-change-route={{this.args.changeRoute}}
                          data-surface-target={{this.args.target}}
                          data-surface-target-scope={{this.args.targetScope}}
                          data-surface-coordinate-space={{this.coordinateSpaceAttribute}}
                          data-surface-coordinate-space-id={{this.coordinateSpaceId}}
                          data-surface-local-coordinate={{this.localCoordinateAttribute}}
                          data-surface-focus-key={{this.focusKey}}
                          data-surface-path={{this.pathAttribute}}
                          data-surface-coordinate={{this.coordinate}}
                          {{surfaceNode
                            this.ladder
                            runtime=this.runtime
                            id=this.id
                            surface=this.surface
                            parentId=this.parentId
                            mode=this.explicitModeAttribute
                            target=this.args.target
                            targetScope=this.args.targetScope
                            focusKey=this.focusKey
                            coordinate=this.coordinate
                            coordinateSpace=this.coordinateSpaceAttribute
                            localCoordinate=this.localCoordinateAttribute
                            coordinateSource=this.coordinateSource
                            keyParts=this.keyParts
                            generatedId=this.usesGeneratedId
                            policy=this.runtimePolicy
                            grid=this.runtimeGridCoordinate
                            expanded=this.args.expanded
                            onSelect=this.args.onSelect
                            onActivate=this.args.onActivate
                            scrollOnSelect=this.args.scrollOnSelect
                            scrollTarget=this.args.scrollTarget
                            scrollAnchor=this.args.scrollAnchor
                            hoverSignal=this.args.hoverSignal
                            hoverAnchor=this.args.hoverAnchor
                            onExpand=this.args.onExpand
                            onCollapse=this.args.onCollapse
                            lift=this.liftEdges
                            liftData=this.args.liftData
                            liftManager=this.liftManager
                            liftActiveSourceId=this.activeLiftSourceId
                            liftActiveTargetId=this.activeLiftTargetId
                            liftActiveKind=this.activeLiftKind
                          }}
                          {{surfaceScopeRelay this.scopeRelay}}
                          {{surfaceInlineEdit
                            enabled=this.inlineEditEnabled
                            activation=this.inlineEditActivation
                            value=this.inlineEditValue
                            label=this.inlineEditLabel
                            multiline=this.inlineEditMultiline
                            onInput=this.inlineEditInput
                          }}
                          ...attributes
                        >
                          {{yield}}
                        </section>
                      {{else}}
                        <div
                          id={{this.id}}
                          data-surface-component={{this.surface}}
                          data-surface-role={{this.args.role}}
                          data-surface-pattern={{this.args.pattern}}
                          data-surface-scope={{this.args.scope}}
                          data-surface-depth={{this.directiveDepthAttribute}}
                          data-surface-expandable={{this.expandableAttribute}}
                          data-surface-expanded={{this.expandedAttribute}}
                          data-surface-mode={{this.explicitModeAttribute}}
                          data-surface-posture={{this.args.posture}}
                          data-surface-inspect={{this.explicitInspectAttribute}}
                          data-surface-change-route={{this.args.changeRoute}}
                          data-surface-target={{this.args.target}}
                          data-surface-target-scope={{this.args.targetScope}}
                          data-surface-coordinate-space={{this.coordinateSpaceAttribute}}
                          data-surface-coordinate-space-id={{this.coordinateSpaceId}}
                          data-surface-local-coordinate={{this.localCoordinateAttribute}}
                          data-surface-focus-key={{this.focusKey}}
                          data-surface-path={{this.pathAttribute}}
                          data-surface-coordinate={{this.coordinate}}
                          {{surfaceNode
                            this.ladder
                            runtime=this.runtime
                            id=this.id
                            surface=this.surface
                            parentId=this.parentId
                            mode=this.explicitModeAttribute
                            target=this.args.target
                            targetScope=this.args.targetScope
                            focusKey=this.focusKey
                            coordinate=this.coordinate
                            coordinateSpace=this.coordinateSpaceAttribute
                            localCoordinate=this.localCoordinateAttribute
                            coordinateSource=this.coordinateSource
                            keyParts=this.keyParts
                            generatedId=this.usesGeneratedId
                            policy=this.runtimePolicy
                            grid=this.runtimeGridCoordinate
                            expanded=this.args.expanded
                            onSelect=this.args.onSelect
                            onActivate=this.args.onActivate
                            scrollOnSelect=this.args.scrollOnSelect
                            scrollTarget=this.args.scrollTarget
                            scrollAnchor=this.args.scrollAnchor
                            hoverSignal=this.args.hoverSignal
                            hoverAnchor=this.args.hoverAnchor
                            onExpand=this.args.onExpand
                            onCollapse=this.args.onCollapse
                            lift=this.liftEdges
                            liftData=this.args.liftData
                            liftManager=this.liftManager
                            liftActiveSourceId=this.activeLiftSourceId
                            liftActiveTargetId=this.activeLiftTargetId
                            liftActiveKind=this.activeLiftKind
                          }}
                          {{surfaceScopeRelay this.scopeRelay}}
                          {{surfaceInlineEdit
                            enabled=this.inlineEditEnabled
                            activation=this.inlineEditActivation
                            value=this.inlineEditValue
                            label=this.inlineEditLabel
                            multiline=this.inlineEditMultiline
                            onInput=this.inlineEditInput
                          }}
                          ...attributes
                        >
                          {{yield}}
                        </div>
                      {{/if}}
                    </ContextProvider>
                  </ContextProvider>
                </ContextProvider>
              </ContextProvider>
            </ContextProvider>
          </ContextProvider>
        </ContextProvider>
      </ContextProvider>
    </ContextProvider>
  </template>
}

export interface EnvironmentSignature extends SurfaceComponentSignature {
  Args: SurfaceComponentSignature['Args'] & {
    ladder?: FocusLadder;
    keyboard?: KeyboardMode;
    mode?: Mode;
    liftResolver?: LiftResolver;
    coordinateDebug?: boolean;
    coordinateDecals?: boolean;
    coordinateDebugOpen?: boolean;
    coordinateDebugView?: CoordinateDebugView;
  };
}

export class Environment extends Component<EnvironmentSignature> {
  private localLadder = createFocusLadder();
  private localRuntime = createSurfaceRuntime();
  private localLiftManager = createLiftManager();
  private generatedId: string | undefined;
  @consume(PathContextName) declare inheritedSurfacePath: Path | undefined;
  @consume(CoordinateSpaceContextName) declare inheritedCoordinateSpace:
    | CoordinateSpaceContext
    | undefined;
  @consume(SurfaceScopeContextName) declare inheritedScopeRelay:
    | SurfaceScopeRelay
    | undefined;
  private localScopeRelay: SurfaceScopeRelay | undefined;

  constructor(owner: Owner, args: EnvironmentSignature['Args']) {
    super(owner, args);
    const endInitialRuntimeBatch = this.localRuntime.beginBatch();
    queueMicrotask(endInitialRuntimeBatch);
  }

  get surface(): LadderSurface {
    return 'space';
  }

  get scopeRelay(): SurfaceScopeRelay {
    let relay = this.localScopeRelay;
    if (!relay || relay.parent !== this.inheritedScopeRelay) {
      relay = createSurfaceScopeRelay(this.inheritedScopeRelay);
      // eslint-disable-next-line ember/no-side-effects
      this.localScopeRelay = relay;
    }
    return relay;
  }

  get spaceIdentity(): Identity | undefined {
    return this.args.space ?? this.args.identity;
  }

  get localCoordinate(): LocalCoordinate | undefined {
    return this.args.coord ?? this.args.at;
  }

  @cached
  get coordinateSchema(): CoordinateSpace | undefined {
    return (
      this.args.schema ??
      this.args.coordinateSpace ??
      (this.spaceIdentity !== undefined
        ? defaultCoordinateSpaceSchema(this.surface)
        : undefined)
    );
  }

  @cached
  get id(): string {
    if (this.args.id) {
      return this.args.id;
    }

    if (this.surfacePath !== undefined) {
      return surfaceIdFromPath('environment', this.surfacePath);
    }

    if (this.spaceIdentity !== undefined) {
      return surfaceId('environment', this.spaceIdentity, ...this.keyParts);
    }

    // eslint-disable-next-line ember/no-side-effects
    this.generatedId ??= nextSurfaceId('environment');
    return this.generatedId;
  }

  @cached
  get focusKey(): string | undefined {
    if (this.args.focusKey) {
      return this.args.focusKey;
    }

    if (this.surfacePath !== undefined) {
      return surfaceFocusKeyFromPath(this.surfacePath);
    }

    if (this.spaceIdentity !== undefined) {
      return surfaceFocusKey(this.spaceIdentity, ...this.keyParts);
    }

    return undefined;
  }

  get pathAttribute(): string | undefined {
    return this.surfacePath !== undefined
      ? surfaceFocusKeyFromPath(this.surfacePath)
      : undefined;
  }

  @cached
  get coordinate(): string | undefined {
    if (
      this.args.coord !== undefined &&
      this.inheritedCoordinateSpace !== undefined
    ) {
      let local = coordinatePartAttribute(this.args.coord);
      return local !== undefined
        ? `${this.inheritedCoordinateSpace.id}[${this.inheritedCoordinateSpace.schema}]:${local}`
        : `${this.inheritedCoordinateSpace.id}[${this.inheritedCoordinateSpace.schema}]`;
    }

    if (this.coordinateSchema !== undefined) {
      let local = coordinatePartAttribute(this.localCoordinate);
      let spaceId = this.coordinateSpaceId;
      return local !== undefined
        ? `${spaceId}[${this.coordinateSchema}]:${local}`
        : `${spaceId}[${this.coordinateSchema}]`;
    }

    if (
      this.localCoordinate !== undefined &&
      this.inheritedCoordinateSpace !== undefined
    ) {
      let local = coordinatePartAttribute(this.localCoordinate);
      return local !== undefined
        ? `${this.inheritedCoordinateSpace.id}[${this.inheritedCoordinateSpace.schema}]:${local}`
        : `${this.inheritedCoordinateSpace.id}[${this.inheritedCoordinateSpace.schema}]`;
    }

    return this.pathAttribute ?? this.args.focusKey;
  }

  get coordinateSpaceAttribute(): string | undefined {
    if (this.coordinateSchema !== undefined) {
      return this.coordinateSchema;
    }

    if (this.localCoordinate !== undefined) {
      return this.inheritedCoordinateSpace?.schema;
    }

    return undefined;
  }

  get localCoordinateAttribute(): string | undefined {
    return coordinatePartAttribute(this.localCoordinate);
  }

  get directiveDepthAttribute(): string | undefined {
    return this.args.depth === undefined ? undefined : String(this.args.depth);
  }

  @cached
  get coordinateSpaceId(): string {
    if (
      this.coordinateSchema === undefined &&
      this.localCoordinate !== undefined &&
      this.inheritedCoordinateSpace !== undefined
    ) {
      return this.inheritedCoordinateSpace.id;
    }

    return this.focusKey ?? this.id;
  }

  get providedCoordinateSpace(): CoordinateSpaceContext | undefined {
    if (this.coordinateSchema !== undefined) {
      return {
        surface: this.surface,
        id: this.focusKey ?? this.id,
        schema: this.coordinateSchema,
      };
    }

    return this.inheritedCoordinateSpace;
  }

  get coordinateSource(): SurfaceCoordinateSource {
    if (
      this.args.surfacePath !== undefined ||
      this.args.focusKey !== undefined ||
      this.args.id !== undefined ||
      this.args.space !== undefined ||
      this.args.schema !== undefined ||
      this.args.coord !== undefined ||
      this.args.coordinateSpace !== undefined ||
      this.args.at !== undefined
    ) {
      return 'explicit';
    }

    if (this.spaceIdentity !== undefined) {
      return 'identity';
    }

    if (this.inheritedSurfacePath !== undefined) {
      return 'context';
    }

    return 'generated';
  }

  get usesGeneratedId(): boolean {
    return (
      this.args.id === undefined &&
      this.spaceIdentity === undefined &&
      this.surfacePath === undefined
    );
  }

  get keyParts(): IdentityPart[] {
    if (Array.isArray(this.args.key)) {
      return this.args.key;
    }

    if (this.args.key !== undefined) {
      return [this.args.key];
    }

    if (Array.isArray(this.args.identityPart)) {
      return this.args.identityPart;
    }

    if (this.args.identityPart !== undefined) {
      return [this.args.identityPart];
    }

    return [];
  }

  get surfacePath(): Path | undefined {
    if (this.args.surfacePath !== undefined) {
      return this.args.surfacePath;
    }

    if (this.spaceIdentity !== undefined) {
      return normalizeSurfacePath(this.spaceIdentity, this.keyParts);
    }

    if (this.inheritedSurfacePath !== undefined) {
      return [...this.inheritedSurfacePath, ...this.keyParts];
    }

    return undefined;
  }

  get ladder(): FocusLadder {
    return this.args.ladder ?? this.localLadder;
  }

  get runtime(): SurfaceRuntime {
    return this.localRuntime;
  }

  @cached
  get runtimeGridCoordinate(): FociGridCoordinate | undefined {
    if (this.args.grid) return this.args.grid;
    if (this.args.gridRow === undefined || this.args.gridCol === undefined) {
      return undefined;
    }
    return {
      row: this.args.gridRow,
      col: this.args.gridCol,
    };
  }

  @cached
  get runtimePolicy(): FociNodePolicy | undefined {
    const policy: FociNodePolicy = {
      ...(this.args.runtimePolicy ?? {}),
    };
    if (this.args.preset !== undefined) policy.preset = this.args.preset;
    if (this.args.aspects !== undefined) policy.aspects = this.args.aspects;
    if (this.args.runtimeTraversal !== undefined) {
      policy.traversal = this.args.runtimeTraversal;
    }
    if (this.args.runtimeTraversalModel !== undefined) {
      policy.traversalModel = this.args.runtimeTraversalModel;
    }
    if (this.args.runtimeSelection !== undefined) {
      policy.selection = this.args.runtimeSelection;
    }
    if (this.args.runtimeKeyboard !== undefined) {
      policy.keyboard = this.args.runtimeKeyboard;
    }
    if (this.args.runtimeMovement !== undefined) {
      policy.movement = this.args.runtimeMovement;
    }
    if (this.args.runtimePointer !== undefined) {
      policy.pointer = this.args.runtimePointer;
    }
    if (this.args.runtimeEdit !== undefined) {
      policy.edit = this.args.runtimeEdit;
    }
    if (this.args.accepts !== undefined) policy.accepts = this.args.accepts;
    if (this.args.payloadType !== undefined) {
      policy.payloadType = this.args.payloadType;
    }

    return Object.keys(policy).length > 0 ? policy : undefined;
  }

  get liftManager(): LiftManager {
    // eslint-disable-next-line ember/no-side-effects
    this.localLiftManager.resolver = this.args.liftResolver;
    return this.localLiftManager;
  }

  get liftTargetComponent(): LiftTargetComponent | undefined {
    return this.liftManager.targetComponent;
  }

  get liftTargetContext(): LiftTargetContext | undefined {
    return this.liftManager.targetContext;
  }

  get activeLiftSourceId(): string | undefined {
    return this.liftManager.activeSourceId;
  }

  get activeLiftTargetId(): string | undefined {
    return this.liftManager.activeTargetId;
  }

  get activeLiftKind(): string | undefined {
    return this.liftManager.kind;
  }

  get activeLiftFocusToken(): number | undefined {
    return this.liftManager.focusToken;
  }

  get demo(): DemoMode {
    return this.args.demo ?? false;
  }

  get mode(): Mode {
    return this.args.mode ?? modeForPosture(this.args.posture) ?? 'use';
  }

  get inspect(): boolean {
    return this.args.inspect ?? this.mode === 'inspect';
  }

  get inspectAttribute(): string {
    return String(this.inspect);
  }

  get changeRoute(): ChangeRoute {
    return this.args.changeRoute ?? 'auto';
  }

  get skipKeyboard(): boolean {
    return (
      this.args.keyboard === false ||
      this.args.keyboard === 'manual' ||
      this.args.keyboard === 'none'
    );
  }

  @provide(LadderContextName)
  get providedLadder(): FocusLadder {
    return this.ladder;
  }

  @provide(SurfaceRuntimeContextName)
  get providedSurfaceRuntime(): SurfaceRuntime {
    return this.runtime;
  }

  @provide(ParentIdContextName)
  get providedParentId(): string {
    return this.id;
  }

  @provide(ParentContextName)
  get providedParentSurface(): LadderSurface {
    return this.surface;
  }

  @provide(DemoContextName)
  get providedDemo(): DemoMode {
    return this.demo;
  }

  @provide(ModeContextName)
  get providedMode(): Mode {
    return this.mode;
  }

  @provide(InspectContextName)
  get providedInspect(): boolean {
    return this.inspect;
  }

  @provide(ChangeRouteContextName)
  get providedChangeRoute(): ChangeRoute {
    return this.changeRoute;
  }

  @provide(PathContextName)
  get providedSurfacePath(): Path | undefined {
    return this.surfacePath;
  }

  @provide(CoordinateSpaceContextName)
  get providedCoordinateSpaceContext(): CoordinateSpaceContext | undefined {
    return this.providedCoordinateSpace;
  }

  @provide(LiftContextName)
  get providedLiftManager(): LiftManager {
    return this.liftManager;
  }

  @provide(SurfaceScopeContextName)
  get providedScopeRelay(): SurfaceScopeRelay {
    return this.scopeRelay;
  }

  <template>
    <ContextProvider @key={{LadderContextName}} @value={{this.ladder}}>
      <ContextProvider
        @key={{SurfaceRuntimeContextName}}
        @value={{this.runtime}}
      >
        <ContextProvider @key={{ParentIdContextName}} @value={{this.id}}>
          <ContextProvider @key={{ParentContextName}} @value={{this.surface}}>
            <ContextProvider @key={{DemoContextName}} @value={{this.demo}}>
              <ContextProvider @key={{ModeContextName}} @value={{this.mode}}>
                <ContextProvider
                  @key={{InspectContextName}}
                  @value={{this.inspect}}
                >
                  <ContextProvider
                    @key={{LiftContextName}}
                    @value={{this.liftManager}}
                  >
                    <ContextProvider
                      @key={{ChangeRouteContextName}}
                      @value={{this.changeRoute}}
                    >
                      <ContextProvider
                        @key={{PathContextName}}
                        @value={{this.surfacePath}}
                      >
                        <ContextProvider
                          @key={{CoordinateSpaceContextName}}
                          @value={{this.providedCoordinateSpace}}
                        >
                          <ContextProvider
                            @key={{SurfaceScopeContextName}}
                            @value={{this.scopeRelay}}
                          >
                            <div
                              id={{this.id}}
                              data-surface-component='environment'
                              data-surface-role={{this.args.role}}
                              data-surface-pattern={{this.args.pattern}}
                              data-surface-scope={{this.args.scope}}
                              data-surface-depth={{this.directiveDepthAttribute}}
                              data-surface-mode={{this.mode}}
                              data-surface-posture={{this.args.posture}}
                              data-surface-inspect={{this.inspectAttribute}}
                              data-surface-change-route={{this.changeRoute}}
                              data-surface-target={{this.args.target}}
                              data-surface-target-scope={{this.args.targetScope}}
                              data-surface-coordinate-space={{this.coordinateSpaceAttribute}}
                              data-surface-coordinate-space-id={{this.coordinateSpaceId}}
                              data-surface-local-coordinate={{this.localCoordinateAttribute}}
                              data-surface-focus-key={{this.focusKey}}
                              data-surface-path={{this.pathAttribute}}
                              data-surface-coordinate={{this.coordinate}}
                              {{surfaceRoot
                                this.ladder
                                runtime=this.runtime
                                skipKeyboard=this.skipKeyboard
                                navigationView=this.args.coordinateDebugView
                              }}
                              {{surfaceNode
                                this.ladder
                                runtime=this.runtime
                                id=this.id
                                surface=this.surface
                                mode=this.mode
                                target=this.args.target
                                targetScope=this.args.targetScope
                                focusKey=this.focusKey
                                coordinate=this.coordinate
                                coordinateSpace=this.coordinateSpaceAttribute
                                localCoordinate=this.localCoordinateAttribute
                                coordinateSource=this.coordinateSource
                                keyParts=this.keyParts
                                generatedId=this.usesGeneratedId
                                policy=this.runtimePolicy
                                grid=this.runtimeGridCoordinate
                                expanded=this.args.expanded
                                onSelect=this.args.onSelect
                                onActivate=this.args.onActivate
                                scrollOnSelect=this.args.scrollOnSelect
                                scrollTarget=this.args.scrollTarget
                                scrollAnchor=this.args.scrollAnchor
                                hoverSignal=this.args.hoverSignal
                                hoverAnchor=this.args.hoverAnchor
                                onExpand=this.args.onExpand
                                onCollapse=this.args.onCollapse
                                lift=this.args.lift
                                liftData=this.args.liftData
                                liftManager=this.liftManager
                                liftActiveSourceId=this.activeLiftSourceId
                                liftActiveTargetId=this.activeLiftTargetId
                                liftActiveKind=this.activeLiftKind
                              }}
                              {{surfaceScopeRelay this.scopeRelay}}
                              {{surfaceInlineEdit
                                enabled=this.args.inlineEdit
                                value=this.args.editValue
                                label=this.args.editLabel
                                multiline=this.args.editMultiline
                                onInput=this.args.onEditInput
                              }}
                              {{surfaceCoordinateDebugger
                                this.ladder
                                runtime=this.runtime
                                enabled=this.args.coordinateDebug
                                decals=this.args.coordinateDecals
                                open=this.args.coordinateDebugOpen
                                view=this.args.coordinateDebugView
                              }}
                              ...attributes
                            >
                              {{yield}}

                              {{#if this.liftTargetComponent}}
                                {{#if this.liftTargetContext}}
                                  {{#let
                                    this.liftTargetComponent
                                    as |LiftTarget|
                                  }}
                                    <Lift
                                      @anchor={{this.liftManager.anchorSelector}}
                                      @open={{this.liftManager.isOpen}}
                                      @kind={{this.liftManager.kind}}
                                      @placementMode={{this.liftManager.placementMode}}
                                      @size={{this.liftManager.size}}
                                      @backdrop={{this.liftManager.backdrop}}
                                      @elevation={{this.liftManager.elevation}}
                                      @keyboardModel={{this.liftManager.keyboardModel}}
                                      @focusToken={{this.activeLiftFocusToken}}
                                      @onDismiss={{this.liftManager.close}}
                                      {{on
                                        'pointerenter'
                                        this.liftManager.cancelDismiss
                                      }}
                                      {{on
                                        'pointerleave'
                                        this.liftManager.scheduleDismissDetails
                                      }}
                                    >
                                      <div
                                        id={{this.liftManager.activeTargetId}}
                                        data-surface-lift-target={{this.liftManager.kind}}
                                        data-surface-lift-source={{this.liftManager.activeSourceId}}
                                        data-surface-preserve-focus
                                      >
                                        <LiftTarget
                                          @context={{this.liftTargetContext}}
                                        />
                                      </div>
                                    </Lift>
                                  {{/let}}
                                {{/if}}
                              {{/if}}
                            </div>
                          </ContextProvider>
                        </ContextProvider>
                      </ContextProvider>
                    </ContextProvider>
                  </ContextProvider>
                </ContextProvider>
              </ContextProvider>
            </ContextProvider>
          </ContextProvider>
        </ContextProvider>
      </ContextProvider>
    </ContextProvider>
  </template>
}

export class Layout extends SurfaceComponent {
  get surface(): LadderSurface {
    return 'layout';
  }
}

export class Canvas extends SurfaceComponent {
  get surface(): LadderSurface {
    return 'canvas';
  }
}

export class Scene extends SurfaceComponent {
  get surface(): LadderSurface {
    return 'scene';
  }
}

export class Grid extends SurfaceComponent {
  get surface(): LadderSurface {
    return 'grid';
  }
}

export class Row extends SurfaceComponent {
  get surface(): LadderSurface {
    return 'row';
  }
}

export class Scroll extends SurfaceComponent {
  get surface(): LadderSurface {
    return 'scroll';
  }
}

export class Flow extends SurfaceComponent {
  get surface(): LadderSurface {
    return 'flow';
  }
}

export class Frame extends SurfaceComponent {
  get surface(): LadderSurface {
    return 'frame';
  }
}

export class Connection extends SurfaceComponent {
  get surface(): LadderSurface {
    return 'connection';
  }
}

export class Pane extends SurfaceComponent {
  get surface(): LadderSurface {
    return 'pane';
  }
}

export class Plane extends SurfaceComponent {
  get surface(): LadderSurface {
    return 'plane';
  }
}

export class Outline extends SurfaceComponent {
  get surface(): LadderSurface {
    return 'outline';
  }
}

export interface CellSignature extends SurfaceComponentSignature {
  Args: SurfaceComponentSignature['Args'] & {
    /** Force a specific chrome surface, skipping DOM detection. */
    surface?: CellSurface;
    state?: CellValidationState;
    disabled?: boolean;
    readonly?: boolean;
    bottomTreatment?: 'flat' | 'rounded';
    /** Omits the outer border so adjacent cells can visually chain. */
    chained?: boolean;
  };
  Blocks: { default: []; pre: []; post: [] };
  Element: HTMLElement;
}

// Each FORM token uses the surfaces semantic slot (e.g. `--border`) WITH
// a boxel-ui native-token fallback (e.g. `--boxel-form-control-border-color`).
// This way the chrome works inside boxel-ui hosts (CardDef edit views, realms)
// that only ship the boxel-ui token layer, and surfaces themes can still
// override by setting the semantic slot.
const FORM_VARS =
  [
    '--cell-padding:var(--boxel-sp-xs) var(--boxel-sp-sm) var(--boxel-sp-xs) var(--boxel-sp-sm)',
    '--cell-border:1px solid var(--border, var(--boxel-form-control-border-color, var(--boxel-300, #d3d3d3)))',
    '--cell-radius:var(--boxel-form-control-border-radius, var(--boxel-border-radius, 10px))',
    '--cell-outline:1px solid transparent',
    '--cell-bg:var(--background, var(--boxel-light, #ffffff))',
    '--cell-fg:var(--foreground, var(--boxel-dark, #000000))',
    '--cell-height:auto',
    '--cell-min-height:var(--boxel-form-control-height, 2.5rem)',
    '--cell-focus-shadow:0 0 0 1px var(--ring, var(--boxel-highlight, #00ffba))',
    '--cell-focus-border:var(--ring, var(--boxel-highlight, #00ffba))',
    '--cell-overflow:grow',
    '--cell-placeholder-color:var(--muted-foreground, var(--boxel-450, #919191))',
    '--cell-error-color:var(--destructive, var(--boxel-error-200, #ff5050))',
    '--cell-helper-color:var(--muted-foreground, var(--boxel-450, #919191))',
    '--boxel-input-height:var(--boxel-form-control-height, 2.5rem)',
    '--boxel-form-control-border-color:var(--border, var(--boxel-300, #d3d3d3))',
    '--boxel-form-control-border-radius:var(--boxel-form-control-border-radius, var(--boxel-border-radius, 10px))',
    '--boxel-form-control-box-shadow:none',
  ].join(';') + ';';

const GRID_VARS =
  [
    '--cell-padding:0 var(--boxel-sp-xs)',
    '--cell-border:0',
    '--cell-radius:0',
    '--cell-outline:1.5px solid var(--ring, var(--boxel-highlight, #00ffba))',
    '--cell-bg:transparent',
    '--cell-fg:inherit',
    '--cell-height:100%',
    '--cell-min-height:0',
    '--cell-focus-shadow:none',
    '--cell-focus-border:inherit',
    '--cell-overflow:lift',
    '--cell-placeholder-color:var(--muted-foreground, var(--boxel-450, #919191))',
    '--cell-error-color:var(--destructive, var(--boxel-error-200, #ff5050))',
    '--cell-helper-color:var(--muted-foreground, var(--boxel-450, #919191))',
    '--boxel-input-height:100%',
    '--boxel-form-control-height:100%',
    '--boxel-form-control-border-color:transparent',
    '--boxel-form-control-border-radius:0',
    '--boxel-form-control-box-shadow:none',
  ].join(';') + ';';

const CANVAS_VARS =
  [
    '--cell-padding:var(--boxel-sp-xs)',
    '--cell-border:0',
    '--cell-radius:var(--boxel-border-radius-xs, 4px)',
    '--cell-outline:0',
    '--cell-bg:transparent',
    '--cell-fg:inherit',
    '--cell-height:auto',
    '--cell-min-height:0',
    '--cell-focus-shadow:0 0 0 1px var(--ring, var(--boxel-highlight, #00ffba))',
    '--cell-focus-border:var(--ring, var(--boxel-highlight, #00ffba))',
    '--cell-overflow:grow',
    '--cell-placeholder-color:var(--muted-foreground, var(--boxel-450, #919191))',
    '--cell-error-color:var(--destructive, var(--boxel-error-200, #ff5050))',
    '--cell-helper-color:var(--muted-foreground, var(--boxel-450, #919191))',
    '--boxel-input-height:auto',
    '--boxel-form-control-border-color:transparent',
    '--boxel-form-control-border-radius:var(--boxel-border-radius-xs, 4px)',
    '--boxel-form-control-box-shadow:none',
  ].join(';') + ';';

const SCENE_VARS =
  [
    '--cell-padding:var(--boxel-sp-sm) var(--boxel-sp)',
    '--cell-border:1px solid color-mix(in oklch, var(--primary-foreground) 18%, transparent)',
    '--cell-radius:var(--boxel-border-radius-sm)',
    '--cell-outline:0',
    '--cell-bg:color-mix(in oklch, var(--primary-foreground) 5%, transparent)',
    '--cell-fg:inherit',
    '--cell-height:auto',
    '--cell-min-height:0',
    '--cell-focus-shadow:0 0 0 1px color-mix(in oklch, var(--primary-foreground) 45%, transparent)',
    '--cell-focus-border:color-mix(in oklch, var(--primary-foreground) 45%, transparent)',
    '--cell-overflow:grow',
    '--cell-placeholder-color:color-mix(in oklch, var(--primary-foreground) 50%, transparent)',
    '--cell-error-color:var(--destructive)',
    '--cell-helper-color:color-mix(in oklch, var(--primary-foreground) 55%, transparent)',
    '--boxel-input-height:auto',
    '--boxel-form-control-border-color:color-mix(in oklch, var(--primary-foreground) 18%, transparent)',
    '--boxel-form-control-border-radius:var(--boxel-border-radius)',
    '--boxel-form-control-box-shadow:none',
  ].join(';') + ';';

const VARS_BY_SURFACE: Record<CellSurface, string> = {
  form: FORM_VARS,
  grid: GRID_VARS,
  canvas: CANVAS_VARS,
  scene: SCENE_VARS,
};

export class Cell extends SurfaceComponent {
  private cellGuid = guidFor(this);

  @consume(FormFieldContextName) declare inheritedFormField:
    | FormFieldContext
    | undefined;

  @tracked private detectedCellSurface: CellSurface = 'form';
  @tracked private detectedState: CellValidationState = 'none';

  get surface(): LadderSurface {
    return 'cell';
  }

  detectCell = modifier((el: HTMLElement) => {
    let formFieldState = el
      .closest('[data-bx-form-field-state]')
      ?.getAttribute('data-bx-form-field-state');
    this.detectedState = isCellValidationState(formFieldState)
      ? formFieldState
      : 'none';

    if (this.args.surface) {
      this.detectedCellSurface = this.args.surface;
      return;
    }

    this.detectedCellSurface = el.closest('[data-bx-grid]')
      ? 'grid'
      : el.closest(
            '[data-bx-canvas-node-id], [data-bx-canvas-edge-id], [data-bx-canvas-runtime-root]',
          )
        ? 'canvas'
        : el.closest('[data-bx-scene-node-id], [data-bx-scene-runtime-root]')
          ? 'scene'
          : 'form';
  });

  get cellSurface(): CellSurface {
    return this.args.surface ?? this.detectedCellSurface;
  }

  get style(): string {
    return VARS_BY_SURFACE[this.cellSurface];
  }

  get overflow(): 'grow' | 'lift' {
    return this.cellSurface === 'grid' ? 'lift' : 'grow';
  }

  get bottomTreatment(): 'flat' | 'rounded' {
    return this.args.bottomTreatment ?? 'rounded';
  }

  get state(): CellValidationState {
    return (
      this.args.state ?? this.inheritedFormField?.state ?? this.detectedState
    );
  }

  get disabled(): boolean {
    return this.args.disabled ?? this.inheritedFormField?.disabled ?? false;
  }

  get readonly(): boolean {
    return this.args.readonly ?? this.inheritedFormField?.readonly ?? false;
  }

  get surfaceRole(): Role {
    return this.args.role ?? 'control';
  }

  get surfaceTarget(): Target {
    return (
      this.args.target ?? (this.cellSurface === 'grid' ? 'range-item' : 'value')
    );
  }

  get defaultFocusOwner(): 'inner' | 'none' {
    return this.cellSurface === 'grid' ? 'none' : 'inner';
  }

  override get keyParts(): IdentityPart[] {
    if (this.args.key !== undefined || this.args.identityPart !== undefined) {
      return super.keyParts;
    }

    let key = this.inheritedFormField?.surfaceKey ?? this.cellGuid;
    return Array.isArray(key) ? key : [key];
  }

  <template>
    <ContextProvider @key={{LadderContextName}} @value={{this.ladder}}>
      <ContextProvider
        @key={{SurfaceRuntimeContextName}}
        @value={{this.runtime}}
      >
        <ContextProvider @key={{ParentIdContextName}} @value={{this.id}}>
          <ContextProvider @key={{ParentContextName}} @value={{this.surface}}>
            <ContextProvider @key={{DemoContextName}} @value={{this.demo}}>
              <ContextProvider @key={{ModeContextName}} @value={{this.mode}}>
                <ContextProvider
                  @key={{InspectContextName}}
                  @value={{this.inspect}}
                >
                  <ContextProvider
                    @key={{LiftContextName}}
                    @value={{this.liftManager}}
                  >
                    <ContextProvider
                      @key={{ChangeRouteContextName}}
                      @value={{this.changeRoute}}
                    >
                      <ContextProvider
                        @key={{PathContextName}}
                        @value={{this.surfacePath}}
                      >
                        <ContextProvider
                          @key={{CoordinateSpaceContextName}}
                          @value={{this.providedCoordinateSpace}}
                        >
                          <ContextProvider
                            @key={{SurfaceScopeContextName}}
                            @value={{this.scopeRelay}}
                          >
                            {{#let
                              (if
                                (has-block 'pre')
                                'outer'
                                (if
                                  (has-block 'post')
                                  'outer'
                                  this.defaultFocusOwner
                                )
                              )
                              as |focusOwner|
                            }}
                              <div
                                id={{this.id}}
                                data-surface-component={{this.surface}}
                                data-surface-role={{this.surfaceRole}}
                                data-surface-pattern={{this.args.pattern}}
                                data-surface-scope={{this.args.scope}}
                                data-surface-depth={{this.directiveDepthAttribute}}
                                data-surface-expandable={{this.expandableAttribute}}
                                data-surface-expanded={{this.expandedAttribute}}
                                data-surface-mode={{this.explicitModeAttribute}}
                                data-surface-posture={{this.args.posture}}
                                data-surface-inspect={{this.explicitInspectAttribute}}
                                data-surface-change-route={{this.args.changeRoute}}
                                data-surface-target={{this.surfaceTarget}}
                                data-surface-target-scope={{this.args.targetScope}}
                                data-surface-coordinate-space={{this.coordinateSpaceAttribute}}
                                data-surface-coordinate-space-id={{this.coordinateSpaceId}}
                                data-surface-local-coordinate={{this.localCoordinateAttribute}}
                                data-surface-focus-key={{this.focusKey}}
                                data-surface-path={{this.pathAttribute}}
                                data-surface-coordinate={{this.coordinate}}
                                class='bx-cell bx-cell--{{this.cellSurface}}'
                                style={{this.style}}
                                data-bx-cell-overflow={{this.overflow}}
                                data-bx-cell-state='idle'
                                data-bx-cell-validation-state={{this.state}}
                                data-bx-cell-focus-owner={{focusOwner}}
                                data-bx-cell-bottom-treatment={{this.bottomTreatment}}
                                data-bx-cell-disabled={{if
                                  this.disabled
                                  'true'
                                }}
                                data-bx-cell-readonly={{if
                                  this.readonly
                                  'true'
                                }}
                                data-bx-cell-chained={{if
                                  this.args.chained
                                  'true'
                                }}
                                {{surfaceNode
                                  this.ladder
                                  runtime=this.runtime
                                  id=this.id
                                  surface=this.surface
                                  parentId=this.parentId
                                  mode=this.explicitModeAttribute
                                  target=this.surfaceTarget
                                  targetScope=this.args.targetScope
                                  focusKey=this.focusKey
                                  coordinate=this.coordinate
                                  coordinateSpace=this.coordinateSpaceAttribute
                                  localCoordinate=this.localCoordinateAttribute
                                  coordinateSource=this.coordinateSource
                                  keyParts=this.keyParts
                                  generatedId=this.usesGeneratedId
                                  policy=this.runtimePolicy
                                  grid=this.runtimeGridCoordinate
                                  expanded=this.args.expanded
                                  onSelect=this.args.onSelect
                                  onActivate=this.args.onActivate
                                  scrollOnSelect=this.args.scrollOnSelect
                                  scrollTarget=this.args.scrollTarget
                                  scrollAnchor=this.args.scrollAnchor
                                  hoverSignal=this.args.hoverSignal
                                  hoverAnchor=this.args.hoverAnchor
                                  onExpand=this.args.onExpand
                                  onCollapse=this.args.onCollapse
                                  lift=this.liftEdges
                                  liftData=this.args.liftData
                                  liftManager=this.liftManager
                                  liftActiveSourceId=this.activeLiftSourceId
                                  liftActiveTargetId=this.activeLiftTargetId
                                  liftActiveKind=this.activeLiftKind
                                }}
                                {{surfaceScopeRelay this.scopeRelay}}
                                {{surfaceInlineEdit
                                  enabled=this.inlineEditEnabled
                                  activation=this.inlineEditActivation
                                  value=this.inlineEditValue
                                  label=this.inlineEditLabel
                                  multiline=this.inlineEditMultiline
                                  onInput=this.inlineEditInput
                                }}
                                {{this.detectCell}}
                                ...attributes
                              >
                                {{#if (has-block 'pre')}}
                                  <span
                                    class='bx-cell__accessory bx-cell__accessory--pre'
                                  >
                                    {{yield to='pre'}}
                                  </span>
                                {{/if}}
                                <span class='bx-cell__content'>
                                  {{yield}}
                                </span>
                                {{#if (has-block 'post')}}
                                  <span
                                    class='bx-cell__accessory bx-cell__accessory--post'
                                  >
                                    {{yield to='post'}}
                                  </span>
                                {{/if}}
                              </div>
                            {{/let}}
                          </ContextProvider>
                        </ContextProvider>
                      </ContextProvider>
                    </ContextProvider>
                  </ContextProvider>
                </ContextProvider>
              </ContextProvider>
            </ContextProvider>
          </ContextProvider>
        </ContextProvider>
      </ContextProvider>
    </ContextProvider>

    <style>
      .bx-cell {
        display: block;
        width: 100%;
        color: var(--cell-fg);
      }

      .bx-cell--grid {
        display: flex;
        min-width: 0;
        height: var(--cell-height);
        overflow: hidden;
      }

      .bx-cell--form,
      .bx-cell--canvas,
      .bx-cell--scene {
        display: block;
        min-height: var(--cell-min-height);
      }

      .bx-cell:has(.bx-cell__accessory) {
        display: grid;
        grid-template-columns: auto minmax(0, 1fr) auto;
        align-items: stretch;
        min-height: var(--cell-min-height);
        border: var(--cell-border);
        border-radius: var(--cell-radius);
        background: var(--cell-bg);
      }

      .bx-cell--grid:has(.bx-cell__accessory) {
        min-height: 0;
        height: var(--cell-height);
      }

      .bx-cell[data-bx-cell-bottom-treatment='flat']:has(.bx-cell__accessory) {
        border-bottom-right-radius: 0;
        border-bottom-left-radius: 0;
      }

      .bx-cell[data-bx-cell-chained='true']:has(.bx-cell__accessory) {
        border: 0;
      }

      .bx-cell__content {
        display: block;
        min-width: 0;
      }

      .bx-cell--grid .bx-cell__content {
        flex: 1 1 auto;
        width: 100%;
        height: 100%;
      }

      .bx-cell--grid .input-container,
      .bx-cell--grid .boxel-input,
      .bx-cell--grid .container,
      .bx-cell--grid .boxel-input-group {
        width: 100%;
        max-width: none;
        height: 100%;
        min-height: 0;
      }

      .bx-cell--grid .boxel-input {
        box-sizing: border-box;
        flex: 1 1 auto;
        border: 0;
        border-radius: 0;
        background: transparent;
        box-shadow: none;
        outline: 0;
        padding: 0 var(--boxel-sp-xs);
      }

      .bx-cell--grid .boxel-input-group {
        border: 0;
        border-radius: 0;
        background: transparent;
      }

      .bx-cell--canvas .boxel-input,
      .bx-cell--canvas .boxel-input-group {
        background: transparent;
        border-color: transparent;
        box-shadow: none;
      }

      .bx-cell--scene .boxel-input,
      .bx-cell--scene .boxel-input-group {
        background: color-mix(
          in oklch,
          var(--primary-foreground) 5%,
          transparent
        );
        color: inherit;
      }

      .bx-cell__content > input,
      .bx-cell__content > select,
      .bx-cell__content > textarea,
      .bx-cell .boxel-input {
        width: 100%;
        min-height: var(--cell-min-height);
        height: var(--cell-height);
        padding: var(--cell-padding);
        border: var(--cell-border);
        border-radius: var(--cell-radius);
        outline: var(--cell-outline);
        background: var(--cell-bg);
        color: var(--cell-fg);
        font: inherit;
      }

      .bx-cell:has(.bx-cell__accessory) .bx-cell__content > input,
      .bx-cell:has(.bx-cell__accessory) .bx-cell__content > select,
      .bx-cell:has(.bx-cell__accessory) .bx-cell__content > textarea,
      .bx-cell:has(.bx-cell__accessory) .boxel-input {
        border: 0;
        border-radius: 0;
        background: transparent;
      }

      .bx-cell__content > input::placeholder,
      .bx-cell__content > textarea::placeholder,
      .bx-cell .boxel-input::placeholder {
        color: var(--cell-placeholder-color);
      }

      .bx-cell[data-bx-cell-focus-owner='inner']
        .bx-cell__content
        > input:focus,
      .bx-cell[data-bx-cell-focus-owner='inner']
        .bx-cell__content
        > select:focus,
      .bx-cell[data-bx-cell-focus-owner='inner']
        .bx-cell__content
        > textarea:focus,
      .bx-cell[data-bx-cell-focus-owner='inner'] .boxel-input:focus {
        border-color: var(--cell-focus-border);
        box-shadow: var(--cell-focus-shadow);
      }

      .bx-cell[data-bx-cell-focus-owner='outer']
        .bx-cell__content
        > input:focus,
      .bx-cell[data-bx-cell-focus-owner='outer']
        .bx-cell__content
        > select:focus,
      .bx-cell[data-bx-cell-focus-owner='outer']
        .bx-cell__content
        > textarea:focus,
      .bx-cell[data-bx-cell-focus-owner='outer'] .boxel-input:focus,
      .bx-cell[data-bx-cell-focus-owner='none'] .bx-cell__content > input:focus,
      .bx-cell[data-bx-cell-focus-owner='none']
        .bx-cell__content
        > select:focus,
      .bx-cell[data-bx-cell-focus-owner='none']
        .bx-cell__content
        > textarea:focus,
      .bx-cell[data-bx-cell-focus-owner='none'] .boxel-input:focus {
        border-color: transparent;
        outline: 0;
        box-shadow: none;
      }

      .bx-cell[data-bx-cell-focus-owner='outer']:has(
          .bx-cell__accessory:focus-within
        ),
      .bx-cell[data-bx-cell-focus-owner='outer']:has(
          .bx-cell__content > input:focus
        ),
      .bx-cell[data-bx-cell-focus-owner='outer']:has(
          .bx-cell__content > select:focus
        ),
      .bx-cell[data-bx-cell-focus-owner='outer']:has(
          .bx-cell__content > textarea:focus
        ) {
        border-color: var(--cell-focus-border);
        box-shadow: var(--cell-focus-shadow);
      }

      .bx-cell__accessory {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        min-height: var(--cell-min-height);
        padding-inline: var(--boxel-sp-sm);
        color: var(--cell-helper-color);
        font-size: var(--boxel-body-font-size);
        white-space: nowrap;
      }

      .bx-cell__accessory--pre {
        border-right: var(--cell-border);
      }

      .bx-cell__accessory--post {
        border-left: var(--cell-border);
      }

      .bx-cell[data-bx-cell-validation-state='invalid']
        .bx-cell__content
        > input,
      .bx-cell[data-bx-cell-validation-state='invalid']
        .bx-cell__content
        > select,
      .bx-cell[data-bx-cell-validation-state='invalid']
        .bx-cell__content
        > textarea,
      .bx-cell[data-bx-cell-validation-state='invalid'] .boxel-input,
      .bx-cell[data-bx-cell-validation-state='invalid']:has(
          .bx-cell__accessory
        ) {
        border-color: var(--cell-error-color);
      }

      .bx-cell[data-bx-cell-state='drag-source'] {
        opacity: 0.4;
        pointer-events: none;
      }

      .bx-cell[data-bx-cell-state='drop-target'] {
        background: color-mix(
          in oklch,
          var(--cell-focus-border) 8%,
          var(--cell-bg)
        );
        border-color: var(--cell-focus-border);
        box-shadow: none;
      }

      .bx-cell[data-bx-cell-state='lift-host'] {
        box-shadow: none;
      }

      .bx-cell[data-bx-cell-disabled='true'],
      .bx-cell[data-bx-cell-readonly='true'] {
        opacity: 0.62;
      }
    </style>
  </template>
}

function isCellValidationState(
  value: string | null | undefined,
): value is CellValidationState {
  return (
    value === 'none' ||
    value === 'valid' ||
    value === 'invalid' ||
    value === 'loading' ||
    value === 'initial'
  );
}

export class Run extends SurfaceComponent {
  get surface(): LadderSurface {
    return 'run';
  }
}

export class Unit extends SurfaceComponent {
  get surface(): LadderSurface {
    return 'unit';
  }
}
