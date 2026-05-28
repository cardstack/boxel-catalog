import type {
  FociActivityLayerSnapshot,
  FociActivityRole,
  FociProjection,
  FociProjectionAdornment,
  FociProjectionNode,
} from './foci-store.ts';

export interface FociProjectionAdapterNode {
  id: string;
  tabIndex: 0 | -1 | null;
  classes?: readonly string[];
  stopReason?: string | null;
  generated?: boolean;
}

export interface FociProjectionAdapterDecal {
  kind: FociProjectionAdornment | string;
  ids: readonly string[];
}

export interface FociProjectionAdapterSnapshot {
  activeDomId: string | null;
  nodes: readonly FociProjectionAdapterNode[];
  decals?: readonly FociProjectionAdapterDecal[];
  layerIds?: readonly string[];
}

export type FociProjectionConformanceSeverity = 'error' | 'warning';

export interface FociProjectionConformanceIssue {
  code: string;
  message: string;
  id?: string;
  severity: FociProjectionConformanceSeverity;
}

export interface FociProjectionNodeConformance {
  id: string;
  traversalStop: boolean;
  traversalReason?: string;
  selectable: boolean;
  editable: boolean;
  receiver: boolean;
  browserFocusable: boolean;
  programmaticFocusable: boolean;
  expectedTabIndex: 0 | -1 | null;
  actualTabIndex: 0 | -1 | null | undefined;
  focused: boolean;
  selected: boolean;
  hovered: boolean;
  focusPath: boolean;
  layerRoles: readonly FociActivityRole[];
  adornments: readonly FociProjectionAdornment[];
  issues: readonly FociProjectionConformanceIssue[];
}

export interface FociProjectionConformanceOptions {
  expectedTraversalIds?: readonly string[] | null;
  generatedIds?: readonly string[];
  activityLayers?: readonly FociActivityLayerSnapshot[];
  requireAllNodes?: boolean;
  requireProjectedDecals?: boolean;
}

export interface FociProjectionConformanceResult {
  ok: boolean;
  semanticIssues: readonly string[];
  visualIssues: readonly string[];
  issues: readonly FociProjectionConformanceIssue[];
  traversalIds: readonly string[];
  adapterTabIds: readonly string[];
  expectedTraversalIds: readonly string[] | null;
  nodes: readonly FociProjectionNodeConformance[];
}

export function validateProjectionConformance(
  projection: FociProjection,
  adapter: FociProjectionAdapterSnapshot,
  options: FociProjectionConformanceOptions = {},
): FociProjectionConformanceResult {
  const requireAllNodes = options.requireAllNodes ?? true;
  const requireProjectedDecals = options.requireProjectedDecals ?? false;
  const adapterNodes = new Map(
    adapter.nodes.map((node) => [node.id, node] as const),
  );
  const adapterTabIds = adapter.nodes
    .filter((node) => node.tabIndex === 0)
    .map((node) => node.id);
  const semanticIssues: string[] = [];
  const visualIssues: string[] = [];
  const issues: FociProjectionConformanceIssue[] = [];
  const nodeReports: FociProjectionNodeConformance[] = [];

  const addSemantic = (code: string, message: string, id?: string): void => {
    semanticIssues.push(message);
    issues.push({ code, message, id, severity: 'error' });
  };
  const addVisual = (code: string, message: string, id?: string): void => {
    visualIssues.push(message);
    issues.push({ code, message, id, severity: 'error' });
  };

  if (!sameIds(projection.traversal.ids, adapterTabIds)) {
    addSemantic(
      'tab-order-mismatch',
      `DOM tabbables ${joinIds(adapterTabIds)} do not match projection traversal ${joinIds(projection.traversal.ids)}`,
    );
  }

  const expectedTraversalIds = options.expectedTraversalIds ?? null;
  if (
    expectedTraversalIds &&
    !sameIds(projection.traversal.ids, expectedTraversalIds)
  ) {
    addSemantic(
      'expected-traversal-mismatch',
      `Projection traversal ${joinIds(projection.traversal.ids)} does not match expected ${joinIds(expectedTraversalIds)}`,
    );
  }

  const focusedId = projection.nodes.find((node) => node.focused)?.id ?? null;
  if (focusedId && adapter.activeDomId !== focusedId) {
    addSemantic(
      'dom-focus-mismatch',
      `DOM focus ${adapter.activeDomId ?? 'none'} does not match projected focus ${focusedId}`,
      focusedId,
    );
  }

  for (const node of projection.nodes) {
    const adapterNode = adapterNodes.get(node.id);
    if (requireAllNodes && !adapterNode) {
      addVisual(
        'missing-node',
        `Missing adapter node for projected surface ${node.id}`,
        node.id,
      );
    }

    const nodeIssues = validateProjectedNode(node, adapterNode);
    for (const issue of nodeIssues) {
      issues.push(issue);
      if (
        issue.code.startsWith('tabindex') ||
        issue.code === 'stop-reason-mismatch'
      ) {
        semanticIssues.push(issue.message);
      } else {
        visualIssues.push(issue.message);
      }
    }

    nodeReports.push({
      id: node.id,
      traversalStop: node.traversalStop,
      traversalReason: node.traversalReason,
      selectable: node.selectable,
      editable: node.editable,
      receiver: node.receiver,
      browserFocusable: node.browserFocusable,
      programmaticFocusable: node.programmaticFocusable,
      expectedTabIndex: node.tabIndex,
      actualTabIndex: adapterNode?.tabIndex,
      focused: node.focused,
      selected: node.selected,
      hovered: node.hovered,
      focusPath: node.focusPath,
      layerRoles: node.layerRoles,
      adornments: node.adornments,
      issues: nodeIssues,
    });
  }

  for (const adapterNode of adapter.nodes) {
    if (!projection.nodeMap.has(adapterNode.id)) {
      addSemantic(
        'unknown-adapter-node',
        `Adapter node ${adapterNode.id} is not present in projection`,
        adapterNode.id,
      );
    }
  }

  for (const generatedId of options.generatedIds ?? []) {
    const adapterNode = adapterNodes.get(generatedId);
    if (!adapterNode?.generated) {
      addVisual(
        'missing-generated-marker',
        `${generatedId} is generated but lacks generated projection marker`,
        generatedId,
      );
    }
  }

  const keyOwners = (options.activityLayers ?? []).filter(
    (layer) => layer.keyOwner,
  );
  if (keyOwners.length > 1) {
    addSemantic(
      'multiple-key-owners',
      `Multiple key owners: ${keyOwners.map((layer) => layer.id).join(', ')}`,
    );
  }

  for (const layer of options.activityLayers ?? []) {
    const adapterNode =
      adapterNodes.get(layer.id) ??
      (layer.sourceId ? adapterNodes.get(layer.sourceId) : undefined);
    const layerVisible = Boolean(
      adapterNode || adapter.layerIds?.includes(layer.id),
    );

    if (!layerVisible) {
      addVisual(
        'missing-layer-projection',
        `Layer ${layer.role}:${layer.id} has no visible adapter projection`,
        layer.id,
      );
      continue;
    }

    if (layer.role === 'input' || layer.role === 'preview') continue;
    if (!adapterNodeHasClass(adapterNode, `is-layer-${layer.role}`)) {
      addVisual(
        'missing-layer-class',
        `${layer.id} missing layer class is-layer-${layer.role}`,
        layer.id,
      );
    }
  }

  if (requireProjectedDecals) {
    for (const decal of projection.visualDecals) {
      if (!adapterDecalExists(adapter.decals ?? [], decal.kind, decal.ids)) {
        addVisual(
          'missing-decal',
          `Missing ${decal.kind} decal for ${joinIds(decal.ids)}`,
        );
      }
    }
  }

  return {
    ok: semanticIssues.length === 0 && visualIssues.length === 0,
    semanticIssues,
    visualIssues,
    issues,
    traversalIds: projection.traversal.ids,
    adapterTabIds,
    expectedTraversalIds,
    nodes: nodeReports,
  };
}

function validateProjectedNode(
  node: FociProjectionNode,
  adapterNode: FociProjectionAdapterNode | undefined,
): FociProjectionConformanceIssue[] {
  if (!adapterNode) return [];
  const issues: FociProjectionConformanceIssue[] = [];
  const add = (code: string, message: string): void => {
    issues.push({ code, message, id: node.id, severity: 'error' });
  };

  if (adapterNode.tabIndex !== node.tabIndex) {
    add(
      'tabindex-mismatch',
      `${node.id} tabindex ${formatTabIndex(adapterNode.tabIndex)} does not match projection ${formatTabIndex(node.tabIndex)}`,
    );
  }
  if (node.traversalReason !== adapterNode.stopReason) {
    add(
      'stop-reason-mismatch',
      `${node.id} stop reason ${adapterNode.stopReason ?? 'none'} does not match projection ${node.traversalReason ?? 'none'}`,
    );
  }
  if (
    node.traversalStop !==
    adapterNodeHasClass(adapterNode, 'is-navigable-target')
  ) {
    add(
      'navigable-class-mismatch',
      `${node.id} navigable class does not match traversal projection`,
    );
  }
  if (node.receiver !== adapterNodeHasClass(adapterNode, 'is-drop-target')) {
    add(
      'receiver-class-mismatch',
      `${node.id} drop-target class does not match receiver projection`,
    );
  }
  if (node.editable !== adapterNodeHasClass(adapterNode, 'is-editable')) {
    add(
      'editable-class-mismatch',
      `${node.id} editable class does not match editable projection`,
    );
  }
  if (
    node.traversalStop &&
    node.editable !== adapterNodeHasClass(adapterNode, 'is-editable-target')
  ) {
    add(
      'editable-target-class-mismatch',
      `${node.id} editable-target class does not match editable traversal projection`,
    );
  }
  if (node.focused !== adapterNodeHasClass(adapterNode, 'is-focused')) {
    add(
      'focused-class-mismatch',
      `${node.id} focused class does not match projection`,
    );
  }
  if (node.focusPath !== adapterNodeHasClass(adapterNode, 'is-focus-path')) {
    add(
      'focus-path-class-mismatch',
      `${node.id} focus-path class does not match projection`,
    );
  }
  if (node.selected !== adapterNodeHasClass(adapterNode, 'is-selected')) {
    add(
      'selected-class-mismatch',
      `${node.id} selected class does not match projection`,
    );
  }
  for (const role of node.layerRoles) {
    if (!adapterNodeHasClass(adapterNode, `is-layer-${role}`)) {
      add(
        'layer-class-mismatch',
        `${node.id} missing projected layer class is-layer-${role}`,
      );
    }
  }

  return issues;
}

function adapterNodeHasClass(
  node: FociProjectionAdapterNode | undefined,
  className: string,
): boolean {
  return Boolean(node?.classes?.includes(className));
}

function adapterDecalExists(
  decals: readonly FociProjectionAdapterDecal[],
  kind: FociProjectionAdornment,
  ids: readonly string[],
): boolean {
  return decals.some((decal) => decal.kind === kind && sameIds(decal.ids, ids));
}

function sameIds(a: readonly string[], b: readonly string[]): boolean {
  return a.length === b.length && a.every((id, index) => id === b[index]);
}

function joinIds(ids: readonly string[]): string {
  return ids.length > 0 ? ids.join(' -> ') : 'none';
}

function formatTabIndex(value: 0 | -1 | null | undefined): string {
  return value === undefined || value === null ? 'none' : String(value);
}
