import { parse, SelectorType, type Selector } from 'css-what';

import type {
  FocusLadder,
  LadderNodeSnapshot,
  LadderSurface,
  Target,
  TargetScope,
} from './focus-ladder.ts';

export type RulePosture = 'use' | 'compose' | 'inspect';

export interface RuleNode {
  id: string;
  surface: LadderSurface;
  parentId: string | null;
  target?: Target;
  targetScope?: TargetScope;
  attributes: Record<string, string>;
  states: {
    focused: boolean;
    selected: boolean;
    hovered: boolean;
    focusPath: boolean;
    posture: RulePosture;
    inspecting: boolean;
  };
}

export interface Rule {
  id: string;
  match: string;
  format: string;
  label?: string;
  priority?: number;
}

export interface ComponentRule<TComponent = unknown> extends Rule {
  use: TComponent;
}

export interface RuleRequest {
  id?: string;
  surface: LadderSurface;
  parentId?: string | null;
  attributes?: Record<string, string | number | boolean | null | undefined>;
  states?: Partial<RuleNode['states']>;
  ancestors?: Array<{
    id?: string;
    surface: LadderSurface;
    attributes?: Record<string, string | number | boolean | null | undefined>;
    states?: Partial<RuleNode['states']>;
  }>;
}

export interface ParsedRule extends Rule {
  selectors: Selector[][];
  specificity: RuleSpecificity;
  sourceOrder: number;
}

export interface RuleSpecificity {
  priority: number;
  relationship: number;
  predicate: number;
  segment: number;
}

export interface RuleMatch {
  node: RuleNode;
  rule: ParsedRule;
  specificity: RuleSpecificity;
}

export interface RuleResolution {
  node: RuleNode;
  matches: RuleMatch[];
  best: RuleMatch | null;
}

export interface RuleGraphOptions {
  root?: ParentNode;
  posture?: RulePosture;
  inspecting?: boolean;
  attributesForNode?: (
    node: LadderNodeSnapshot,
    element: HTMLElement | null,
  ) => Record<string, string | number | boolean | null | undefined>;
}

const postureByMode = {
  use: 'use',
  inspect: 'use',
  change: 'compose',
} as const;

function surfaceElementById(
  id: string,
  root: ParentNode = document,
): HTMLElement | null {
  if (typeof CSS !== 'undefined' && CSS.escape) {
    return root.querySelector<HTMLElement>(
      `[data-ladder-id="${CSS.escape(id)}"]`,
    );
  }

  for (const element of root.querySelectorAll<HTMLElement>(
    '[data-ladder-id]',
  )) {
    if (element.getAttribute('data-ladder-id') === id) return element;
  }

  return null;
}

function normalizeAttributeValue(value: unknown): string | undefined {
  if (value === null || value === undefined || value === false)
    return undefined;
  if (value === true) return 'true';
  return String(value);
}

function postureForElement(
  element: HTMLElement | null,
  fallback: RulePosture,
): RulePosture {
  const mode = element
    ?.closest<HTMLElement>('[data-surface-mode]')
    ?.getAttribute('data-surface-mode');
  return mode && mode in postureByMode
    ? postureByMode[mode as keyof typeof postureByMode]
    : fallback;
}

function inspectingForElement(
  element: HTMLElement | null,
  fallback: boolean,
): boolean {
  const inspect = element
    ?.closest<HTMLElement>('[data-surface-inspect]')
    ?.getAttribute('data-surface-inspect');
  return (
    inspect === '' ||
    inspect === 'true' ||
    (inspect === null &&
      element
        ?.closest<HTMLElement>('[data-surface-mode]')
        ?.getAttribute('data-surface-mode') === 'inspect') ||
    (inspect === null && fallback)
  );
}

function attributesFromElement(
  node: LadderNodeSnapshot,
  element: HTMLElement | null,
  options: RuleGraphOptions,
): Record<string, string> {
  const attrs: Record<string, string> = {
    id: node.id,
    surface: node.surface,
    kind: node.surface,
  };

  if (node.target) attrs['target'] = node.target;
  if (node.targetScope) attrs['targetScope'] = node.targetScope;

  if (element) {
    for (const attr of Array.from(element.attributes)) {
      if (attr.name.startsWith('data-surface-')) {
        attrs[attr.name.slice('data-surface-'.length)] = attr.value;
      } else if (attr.name.startsWith('data-rule-')) {
        attrs[attr.name.slice('data-rule-'.length)] = attr.value;
      } else if (attr.name === 'class') {
        attrs['class'] = attr.value;
      } else if (attr.name === 'role') {
        attrs['role'] = attr.value;
      } else if (attr.name === 'aria-label') {
        attrs['label'] = attr.value;
      }
    }
  }

  const extra = options.attributesForNode?.(node, element) ?? {};
  for (const [key, value] of Object.entries(extra)) {
    const normalized = normalizeAttributeValue(value);
    if (normalized !== undefined) attrs[key] = normalized;
  }

  return attrs;
}

export function ruleNodesFromLadder(
  ladder: FocusLadder,
  options: RuleGraphOptions = {},
): RuleNode[] {
  const root =
    options.root ?? (typeof document !== 'undefined' ? document : undefined);
  const fallbackPosture = options.posture ?? 'use';
  const fallbackInspecting = options.inspecting ?? false;

  return ladder.treeSnapshot().map((snapshot) => {
    const element = root ? surfaceElementById(snapshot.id, root) : null;
    const posture = postureForElement(element, fallbackPosture);
    const inspecting = inspectingForElement(element, fallbackInspecting);

    return {
      id: snapshot.id,
      surface: snapshot.surface,
      parentId: snapshot.parentId,
      target: snapshot.target,
      targetScope: snapshot.targetScope,
      attributes: attributesFromElement(snapshot, element, options),
      states: {
        focused: snapshot.focused,
        selected: snapshot.selected,
        hovered: snapshot.hovered,
        focusPath: snapshot.onFocusPath,
        posture,
        inspecting,
      },
    };
  });
}

export function parseRules(rules: Rule[]): ParsedRule[] {
  return rules.map((rule, index) => {
    const selectors = parse(rule.match);
    return {
      ...rule,
      selectors,
      specificity: specificityForSelectors(selectors, rule.priority ?? 0),
      sourceOrder: index,
    };
  });
}

export function resolveRules(
  nodes: RuleNode[],
  rules: Rule[] | ParsedRule[],
): RuleResolution[] {
  const parsed = isParsedSurfaceRules(rules) ? rules : parseRules(rules);
  const byId = new Map(nodes.map((node) => [node.id, node]));

  return nodes.map((node) => {
    const matches = parsed
      .filter((rule) => ruleMatchesNode(rule, node, byId))
      .map((rule) => ({
        node,
        rule,
        specificity: rule.specificity,
      }));

    matches.sort(compareRuleMatches);

    return {
      node,
      matches,
      best: matches[matches.length - 1] ?? null,
    };
  });
}

export function bestRuleFor(
  id: string,
  nodes: RuleNode[],
  rules: Rule[] | ParsedRule[],
): RuleMatch | null {
  return (
    resolveRules(nodes, rules).find((resolution) => resolution.node.id === id)
      ?.best ?? null
  );
}

export function surfaceFor<TComponent>(
  rules: ComponentRule<TComponent>[],
  request: RuleRequest,
  fallback: TComponent,
): TComponent {
  const nodes = ruleNodesFromRequest(request);
  const target = nodes[nodes.length - 1];
  if (!target) return fallback;

  const best = bestRuleFor(target.id, nodes, rules);
  if (!best) return fallback;

  const rule = rules.find((candidate) => candidate.id === best.rule.id);
  return rule?.use ?? fallback;
}

export function ruleNodesFromRequest(request: RuleRequest): RuleNode[] {
  const posture = request.states?.posture ?? 'use';
  const inspecting = request.states?.inspecting ?? posture === 'inspect';
  const ancestors = request.ancestors ?? [];
  const nodes: RuleNode[] = [];
  let parentId: string | null = request.parentId ?? null;

  for (let index = 0; index < ancestors.length; index += 1) {
    const ancestor = ancestors[index]!;
    const id = ancestor.id ?? `${ancestor.surface}:${index}`;
    nodes.push({
      id,
      surface: ancestor.surface,
      parentId,
      attributes: normalizeAttributes({
        ...(ancestor.attributes ?? {}),
        surface: ancestor.surface,
        kind: ancestor.surface,
      }),
      states: normalizeStates(ancestor.states, posture, inspecting),
    });
    parentId = id;
  }

  const id = request.id ?? `${request.surface}:request`;
  nodes.push({
    id,
    surface: request.surface,
    parentId,
    attributes: normalizeAttributes({
      ...(request.attributes ?? {}),
      surface: request.surface,
      kind: request.surface,
    }),
    states: normalizeStates(request.states, posture, inspecting),
  });

  return nodes;
}

function normalizeAttributes(
  attributes: Record<string, string | number | boolean | null | undefined>,
): Record<string, string> {
  const normalized: Record<string, string> = {};
  for (const [key, value] of Object.entries(attributes)) {
    const next = normalizeAttributeValue(value);
    if (next !== undefined) normalized[key] = next;
  }
  return normalized;
}

function normalizeStates(
  states: Partial<RuleNode['states']> | undefined,
  posture: RulePosture,
  inspecting: boolean,
): RuleNode['states'] {
  const explicitPosture = states?.posture ?? posture;
  const normalizedPosture =
    explicitPosture === 'inspect' ? 'use' : explicitPosture;
  return {
    focused: states?.focused ?? false,
    selected: states?.selected ?? false,
    hovered: states?.hovered ?? false,
    focusPath: states?.focusPath ?? false,
    posture: normalizedPosture,
    inspecting:
      states?.inspecting ?? (inspecting || explicitPosture === 'inspect'),
  };
}

function isParsedSurfaceRules(
  rules: Rule[] | ParsedRule[],
): rules is ParsedRule[] {
  return rules.every((rule) => 'selectors' in rule);
}

function ruleMatchesNode(
  rule: ParsedRule,
  node: RuleNode,
  byId: Map<string, RuleNode>,
): boolean {
  return rule.selectors.some((selector) =>
    selectorBranchMatchesNode(selector, selector.length - 1, node, byId),
  );
}

function selectorBranchMatchesNode(
  selector: Selector[],
  tokenIndex: number,
  node: RuleNode | undefined,
  byId: Map<string, RuleNode>,
): boolean {
  if (!node) return false;

  let index = tokenIndex;
  while (index >= 0) {
    const token = selector[index]!;

    if (token.type === SelectorType.Child) {
      return selectorBranchMatchesNode(
        selector,
        index - 1,
        byId.get(node.parentId ?? ''),
        byId,
      );
    }

    if (token.type === SelectorType.Descendant) {
      let ancestor = byId.get(node.parentId ?? '');
      while (ancestor) {
        if (selectorBranchMatchesNode(selector, index - 1, ancestor, byId)) {
          return true;
        }
        ancestor = byId.get(ancestor.parentId ?? '');
      }
      return false;
    }

    if (!simpleTokenMatchesNode(token, node)) return false;
    index -= 1;
  }

  return true;
}

function simpleTokenMatchesNode(token: Selector, node: RuleNode): boolean {
  switch (token.type) {
    case SelectorType.Tag:
      return (
        token.name === '*' ||
        token.name === node.surface ||
        token.name === node.attributes['component'] ||
        token.name === node.attributes['kind']
      );

    case SelectorType.Universal:
      return true;

    case SelectorType.Attribute:
      return attributeSelectorMatchesNode(token, node);

    case SelectorType.Pseudo:
      return pseudoSelectorMatchesNode(token.name, node);

    default:
      return false;
  }
}

function attributeSelectorMatchesNode(
  token: Extract<Selector, { type: SelectorType.Attribute }>,
  node: RuleNode,
): boolean {
  const actual = node.attributes[token.name];
  switch (token.action) {
    case 'exists':
      return actual !== undefined;
    case 'equals':
      return actual === token.value;
    case 'element':
      return actual?.split(/\s+/).includes(token.value) ?? false;
    case 'start':
      return actual?.startsWith(token.value) ?? false;
    case 'end':
      return actual?.endsWith(token.value) ?? false;
    case 'any':
      return actual?.includes(token.value) ?? false;
    case 'hyphen':
      return (
        actual === token.value || actual?.startsWith(`${token.value}-`) === true
      );
    case 'not':
      return actual !== token.value;
    default:
      return false;
  }
}

function pseudoSelectorMatchesNode(name: string, node: RuleNode): boolean {
  switch (name) {
    case 'focused':
    case 'focus':
      return node.states.focused;
    case 'selected':
      return node.states.selected;
    case 'hovered':
    case 'hover':
      return node.states.hovered;
    case 'focus-path':
      return node.states.focusPath;
    case 'use':
    case 'compose':
      return node.states.posture === name;
    case 'inspect':
    case 'inspecting':
      return node.states.inspecting;
    default:
      return false;
  }
}

function specificityForSelectors(
  selectors: Selector[][],
  priority: number,
): RuleSpecificity {
  const sorted = selectors
    .map((selector) => specificityForSelector(selector, priority))
    .sort(compareSpecificity);
  return sorted[sorted.length - 1]!;
}

function specificityForSelector(
  selector: Selector[],
  priority: number,
): RuleSpecificity {
  let relationship = 0;
  let predicate = 0;
  let segment = 0;

  for (const token of selector) {
    switch (token.type) {
      case SelectorType.Child:
        relationship += 10;
        break;
      case SelectorType.Descendant:
        relationship += 3;
        break;
      case SelectorType.Attribute:
        predicate += 10;
        break;
      case SelectorType.Pseudo:
        predicate += 8;
        break;
      case SelectorType.Tag:
        segment += token.name === '*' ? -1 : 5;
        break;
      case SelectorType.Universal:
        segment -= 1;
        break;
    }
  }

  return { priority, relationship, predicate, segment };
}

function compareRuleMatches(a: RuleMatch, b: RuleMatch): number {
  const specificity = compareSpecificity(a.specificity, b.specificity);
  if (specificity !== 0) return specificity;
  return a.rule.sourceOrder - b.rule.sourceOrder;
}

function compareSpecificity(a: RuleSpecificity, b: RuleSpecificity): number {
  return (
    a.priority - b.priority ||
    a.relationship - b.relationship ||
    a.predicate - b.predicate ||
    a.segment - b.segment
  );
}
