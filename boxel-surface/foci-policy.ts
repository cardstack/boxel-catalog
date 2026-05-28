import type {
  FociDestinationSnapshot,
  FociEditPolicy,
  FociKeyboardPolicy,
  FociMode,
  FociModeProjection,
  FociMovementPolicy,
  FociNodePolicy,
  FociNodeRegistration,
  FociPreset,
  FociPresetAspect,
  FociSelectionPolicy,
  FociTraversalModel,
} from './foci-store.ts';
import type { LadderSurface } from './focus-ladder.ts';

export interface FociPresetDefaults {
  aspects: readonly FociPresetAspect[];
  modeProjection: FociModeProjection;
  traversalModel?: FociTraversalModel;
  chrome?: FociNodePolicy['chrome'];
  movement?: FociMovementPolicy;
  sheetCells?: boolean;
  canvasFrames?: boolean;
  canvasEdges?: boolean;
  rowStops?: boolean;
  rowValueProjection?: boolean;
  destinationKind?: FociDestinationSnapshot['targetKind'];
}

export type FociModeAspectFacts = Readonly<
  Record<FociMode, readonly FociPresetAspect[]>
>;

export interface CompiledFociNode {
  id: string;
  parentId: string | null;
  surface: LadderSurface;
  target: FociNodeRegistration['target'];
  targetScope: FociNodeRegistration['targetScope'];
  focusKey: string | undefined;
  scopeId: string | undefined;
  scopeKind: FociNodeRegistration['scopeKind'];
  policy: FociNodePolicy;
  grid: FociNodeRegistration['grid'];
  coordinateSpaceId: string | undefined;
  localCoordinate: unknown;
  children: readonly string[];
  inheritedAspects: readonly FociPresetAspect[];
  inheritedAspectsByMode: FociModeAspectFacts;
  inheritedTraversalModel: FociTraversalModel | null;
  effectiveMovement: FociMovementPolicy;
  movementOwnerId: string | null;
  presetDefaults: FociPresetDefaults;
  sheetCellDefault: boolean | undefined;
  canvasFrameDefault: boolean | undefined;
  canvasEdgeDefault: boolean | undefined;
  rowStopDefault: boolean;
  rowValueProjectionDefault: boolean;
  destinationKindDefault: FociDestinationSnapshot['targetKind'] | undefined;
}

export interface FociProgramDiagnostic {
  code: string;
  id?: string;
  message: string;
}

export interface CompiledFociProgram {
  nodes: readonly CompiledFociNode[];
  nodeMap: ReadonlyMap<string, CompiledFociNode>;
  diagnostics: readonly FociProgramDiagnostic[];
}

const EMPTY_PRESET_DEFAULTS: FociPresetDefaults = {
  aspects: [],
  modeProjection: {},
};

const FOCI_MODES = [
  'use',
  'change',
  'inspect',
  'debug',
] as const satisfies readonly FociMode[];

export const FOCI_PRESET_DEFAULTS = {
  sheet: {
    aspects: ['sheet'],
    modeProjection: {},
    movement: 'engine',
    sheetCells: true,
  },
  grid: {
    aspects: ['sheet'],
    modeProjection: {},
    movement: 'engine',
    sheetCells: true,
  },
  table: {
    aspects: [],
    modeProjection: {},
    movement: 'engine',
    sheetCells: false,
  },
  collection: {
    aspects: [],
    modeProjection: {},
    movement: 'engine',
    rowStops: true,
  },
  properties: {
    aspects: [],
    modeProjection: {},
    movement: 'engine',
    rowStops: true,
    rowValueProjection: true,
  },
  bare: {
    aspects: ['bare'],
    modeProjection: {},
    chrome: 'bare',
  },
  kanban: {
    aspects: [],
    modeProjection: { change: ['reorder'] },
    rowStops: true,
    destinationKind: 'kanban-gap',
  },
  dashboard: {
    aspects: ['place'],
    modeProjection: { change: ['place'] },
    destinationKind: 'dashboard-slot',
  },
  canvas: {
    aspects: ['object'],
    modeProjection: { change: ['place', 'connect'] },
    movement: 'surface',
    canvasFrames: true,
    canvasEdges: true,
  },
  scene: {
    aspects: ['object', 'viewport'],
    modeProjection: { change: ['place'] },
  },
  outline: EMPTY_PRESET_DEFAULTS,
  layout: EMPTY_PRESET_DEFAULTS,
  page: {
    aspects: [],
    modeProjection: {},
    traversalModel: 'document',
  },
  notebook: {
    aspects: [],
    modeProjection: {},
    traversalModel: 'document',
  },
  tools: {
    aspects: ['tools'],
    modeProjection: {},
    traversalModel: 'tools',
  },
  adorn: EMPTY_PRESET_DEFAULTS,
} satisfies Record<FociPreset, FociPresetDefaults>;

export function compileFociPolicy(
  registration: FociNodeRegistration,
): FociNodePolicy {
  const policy = { ...registration.policy };
  const presetDefaults = presetDefaultsFor(policy.preset);
  if (presetDefaults.chrome && !policy.chrome) {
    policy.chrome = presetDefaults.chrome;
  }
  if (presetDefaults.movement && !policy.movement) {
    policy.movement = presetDefaults.movement;
  }
  if (presetDefaults.traversalModel && !policy.traversalModel) {
    policy.traversalModel = presetDefaults.traversalModel;
  }
  if (presetDefaults.aspects.length > 0 || policy.aspects) {
    policy.aspects = uniqueAspects([
      ...presetDefaults.aspects,
      ...(policy.aspects ?? []),
    ]);
  }
  const projectedModes = Object.keys(
    presetDefaults.modeProjection,
  ) as FociMode[];
  if (projectedModes.length > 0 || policy.modeProjection) {
    policy.modeProjection = mergeModeProjection(
      presetDefaults.modeProjection,
      policy.modeProjection,
    );
  }
  if (policy.chrome === 'inert') policy.pointer = 'preview-only';
  if (policy.chrome === 'bare' && !policy.pointer) {
    policy.pointer = 'surface-owned';
  }
  if (policy.chrome === 'cell' && !policy.pointer) {
    policy.pointer = 'cell-owned';
  }
  if (!policy.pointer) policy.pointer = 'transparent';
  if (!policy.selection) {
    policy.selection = defaultSelectionFor(registration);
  }
  if (!policy.keyboard) policy.keyboard = defaultKeyboardFor(registration);
  if (!policy.movement) policy.movement = 'auto';
  if (policy.movement === 'auto') {
    policy.movement = defaultMovementFor(registration, policy);
  }
  if (!policy.edit) policy.edit = defaultEditFor(registration);
  if (!policy.lift) policy.lift = 'none';
  return policy;
}

export function compileFociProgram(
  registrations: readonly FociNodeRegistration[],
): CompiledFociProgram {
  const parentById = new Map<string, string | null>();
  const registrationsById = new Map<string, FociNodeRegistration>();
  const childrenById = new Map<string | null, string[]>();
  const diagnostics: FociProgramDiagnostic[] = [];

  for (const registration of registrations) {
    if (registrationsById.has(registration.id)) {
      diagnostics.push({
        code: 'duplicate-id',
        id: registration.id,
        message: `Duplicate surface id ${registration.id}`,
      });
    }
    registrationsById.set(registration.id, registration);
    parentById.set(registration.id, registration.parentId);
    const siblings = childrenById.get(registration.parentId)?.slice() ?? [];
    siblings.push(registration.id);
    childrenById.set(registration.parentId, siblings);
  }

  for (const registration of registrations) {
    if (
      registration.parentId !== null &&
      !registrationsById.has(registration.parentId)
    ) {
      diagnostics.push({
        code: 'missing-parent',
        id: registration.id,
        message: `${registration.id} references missing parent ${registration.parentId}`,
      });
    }
  }

  const nodeMap = new Map<string, CompiledFociNode>();
  const policiesById = new Map<string, FociNodePolicy>();
  for (const registration of registrations) {
    policiesById.set(registration.id, compileFociPolicy(registration));
  }

  const nodes = registrations.map((registration) => {
    const policy =
      policiesById.get(registration.id) ?? compileFociPolicy(registration);
    const path = pathTo(registration.id, parentById, registrationsById);
    const pathRegistrations = path
      .map((id) => registrationsById.get(id))
      .filter((node): node is FociNodeRegistration => Boolean(node));
    const pathPolicies = pathRegistrations.map((node) => {
      return policiesById.get(node.id) ?? compileFociPolicy(node);
    });
    const inheritedAspectsByMode = inheritedAspectsForPath(pathPolicies);
    const inheritedAspects = inheritedAspectsByMode.use;
    const inheritedTraversalModel =
      pathPolicies
        .map((nodePolicy) => {
          return (
            nodePolicy.traversalModel ??
            (nodePolicy.traversal === 'boundary' ? 'boundary' : undefined)
          );
        })
        .reverse()
        .find((model) => model !== null && model !== undefined) ?? null;
    const movementOwner = pathRegistrations
      .map((node, index) => {
        const compiledPolicy = pathPolicies[index] ?? compileFociPolicy(node);
        return {
          id: node.id,
          movement: compiledPolicy.movement ?? 'auto',
        };
      })
      .reverse()
      .find((entry) => entry.movement !== 'auto');
    const presetDefaults = presetDefaultsFor(policy.preset);
    const sheetCellDefault = inheritedPresetDefault(
      pathRegistrations,
      'sheetCells',
    );
    if (sheetCellDefault === true && registration.surface === 'cell') {
      const explicit = registration.policy ?? {};
      if (explicit.chrome === undefined) policy.chrome = 'cell';
      if (explicit.pointer === undefined) policy.pointer = 'cell-owned';
      if (explicit.selection === undefined) policy.selection = 'grid-cell';
      if (registration.grid && explicit.keyboard === undefined) {
        policy.keyboard = 'grid-cell';
      }
    }
    const canvasFrameDefault = inheritedPresetDefault(
      pathRegistrations,
      'canvasFrames',
    );
    if (
      canvasFrameDefault === true &&
      (registration.surface === 'frame' ||
        registration.surface === 'connection')
    ) {
      const explicit = registration.policy ?? {};
      if (explicit.pointer === undefined) policy.pointer = 'surface-owned';
      if (explicit.selection === undefined) policy.selection = 'object';
      if (explicit.keyboard === undefined) policy.keyboard = 'canvas';
      if (explicit.movement === undefined) policy.movement = 'surface';
    }
    const canvasEdgeDefault = inheritedPresetDefault(
      pathRegistrations,
      'canvasEdges',
    );
    if (canvasEdgeDefault === true && registration.surface === 'connection') {
      const explicit = registration.policy ?? {};
      if (explicit.decalShape === undefined) policy.decalShape = 'path';
      if (explicit.selection === undefined) policy.selection = 'object';
      if (explicit.keyboard === undefined) policy.keyboard = 'canvas';
    }
    const rowStopDefault =
      inheritedPresetDefault(pathRegistrations, 'rowStops') === true;
    const rowValueProjectionDefault =
      inheritedPresetDefault(pathRegistrations, 'rowValueProjection') === true;
    const destinationKindDefault = inheritedPresetDefault(
      pathRegistrations,
      'destinationKind',
    );
    const compiled: CompiledFociNode = {
      id: registration.id,
      parentId: registration.parentId,
      surface: registration.surface,
      target: registration.target,
      targetScope: registration.targetScope,
      focusKey: registration.focusKey,
      scopeId: registration.scopeId,
      scopeKind: registration.scopeKind,
      policy,
      grid: registration.grid,
      coordinateSpaceId: registration.coordinateSpaceId,
      localCoordinate: registration.localCoordinate,
      children: childrenById.get(registration.id) ?? [],
      inheritedAspects,
      inheritedAspectsByMode,
      inheritedTraversalModel,
      effectiveMovement: movementOwner?.movement ?? 'auto',
      movementOwnerId: movementOwner?.id ?? null,
      presetDefaults,
      sheetCellDefault,
      canvasFrameDefault,
      canvasEdgeDefault,
      rowStopDefault,
      rowValueProjectionDefault,
      destinationKindDefault,
    };
    nodeMap.set(registration.id, compiled);
    return compiled;
  });

  return { nodes, nodeMap, diagnostics };
}

function inheritedAspectsForPath(
  pathPolicies: readonly FociNodePolicy[],
): FociModeAspectFacts {
  return Object.fromEntries(
    FOCI_MODES.map((mode) => [
      mode,
      uniqueAspects(
        pathPolicies.flatMap((policy) => [
          ...(policy.aspects ?? []),
          ...(policy.modeProjection?.[mode] ?? []),
        ]),
      ),
    ]),
  ) as unknown as FociModeAspectFacts;
}

export function presetDefaultsFor(
  preset: FociPreset | undefined,
): FociPresetDefaults {
  return preset ? FOCI_PRESET_DEFAULTS[preset] : EMPTY_PRESET_DEFAULTS;
}

export function aspectsForPreset(
  preset: FociPreset | undefined,
  mode: FociMode,
): readonly FociPresetAspect[] {
  const defaults = presetDefaultsFor(preset);
  return [...defaults.aspects, ...(defaults.modeProjection[mode] ?? [])];
}

export function traversalModelForPreset(
  preset: FociPreset | undefined,
): FociTraversalModel | null {
  return presetDefaultsFor(preset).traversalModel ?? null;
}

function pathTo(
  id: string,
  parentById: ReadonlyMap<string, string | null>,
  registrationsById: ReadonlyMap<string, FociNodeRegistration>,
): string[] {
  const path: string[] = [];
  let cursor: string | null | undefined = id;
  const seen = new Set<string>();
  while (cursor && registrationsById.has(cursor) && !seen.has(cursor)) {
    seen.add(cursor);
    path.unshift(cursor);
    cursor = parentById.get(cursor);
  }
  return path;
}

function inheritedPresetDefault<K extends keyof FociPresetDefaults>(
  path: readonly FociNodeRegistration[],
  key: K,
): FociPresetDefaults[K] | undefined {
  for (const node of path.slice().reverse()) {
    const preset = node.policy?.preset;
    if (!preset) continue;
    const value = presetDefaultsFor(preset)[key];
    if (value !== undefined) return value;
  }
  return undefined;
}

function defaultSelectionFor(
  registration: FociNodeRegistration,
): FociSelectionPolicy {
  switch (registration.target) {
    case 'action':
    case 'chrome':
    case 'debug':
    case 'structure':
      return 'none';
    case 'object':
      if (
        registration.surface === 'frame' ||
        registration.surface === 'connection'
      ) {
        return 'object';
      }
      if (
        registration.surface === 'layout' ||
        registration.surface === 'grid' ||
        registration.surface === 'canvas' ||
        registration.surface === 'scene' ||
        registration.surface === 'outline' ||
        registration.surface === 'space'
      ) {
        return 'none';
      }
      return 'single';
    case 'field':
      return registration.grid ? 'grid-cell' : 'single';
    case 'range-item':
      return registration.surface === 'row' ? 'row' : 'single';
    case 'value':
      return 'none';
  }

  switch (registration.surface) {
    case 'cell':
      return 'grid-cell';
    case 'row':
      return 'row';
    case 'frame':
    case 'connection':
      return 'object';
    case 'layout':
    case 'grid':
    case 'canvas':
    case 'scene':
    case 'outline':
    case 'space':
      return 'none';
    default:
      return registration.target === 'action' ? 'none' : 'single';
  }
}

function defaultEditFor(registration: FociNodeRegistration): FociEditPolicy {
  if (registration.target === 'field') return 'inline';
  return 'none';
}

function defaultKeyboardFor(
  registration: Pick<FociNodeRegistration, 'surface' | 'grid'>,
): FociKeyboardPolicy {
  if (registration.grid) return 'grid-cell';
  switch (registration.surface) {
    case 'cell':
      return 'tree';
    case 'row':
      return 'row-list';
    case 'canvas':
    case 'frame':
    case 'connection':
      return 'canvas';
    case 'scene':
      return 'scene';
    case 'outline':
      return 'outline';
    default:
      return 'tree';
  }
}

function defaultMovementFor(
  registration: FociNodeRegistration,
  policy: FociNodePolicy,
): FociMovementPolicy {
  if (
    registration.surface === 'canvas' ||
    registration.surface === 'scene' ||
    policy.preset === 'canvas' ||
    policy.preset === 'scene'
  ) {
    return 'surface';
  }
  return 'auto';
}

function uniqueAspects(
  aspects: readonly FociPresetAspect[],
): readonly FociPresetAspect[] {
  return [...new Set(aspects)];
}

function mergeModeProjection(
  defaults: FociModeProjection,
  explicit: FociModeProjection | undefined,
): FociModeProjection {
  const merged: FociModeProjection = {};
  for (const mode of ['use', 'change', 'inspect', 'debug'] as const) {
    const aspects = uniqueAspects([
      ...(defaults[mode] ?? []),
      ...(explicit?.[mode] ?? []),
    ]);
    if (aspects.length > 0) merged[mode] = aspects;
  }
  return merged;
}
