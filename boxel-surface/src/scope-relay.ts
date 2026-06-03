export interface SurfaceScopeAttribute {
  name: string;
  value: string;
}

export type SurfaceScopeAttributes = readonly SurfaceScopeAttribute[];

const SCOPED_CSS_ATTRIBUTE = /^data-scopedcss-[0-9a-f]{10}-[0-9a-f]{10}$/;

export const SurfaceScopeContextName = 'boxel-surface:scope';

export class SurfaceScopeRelay {
  private local = new Map<string, string>();
  readonly parent?: SurfaceScopeRelay;

  constructor(parent?: SurfaceScopeRelay) {
    this.parent = parent;
  }

  get attributes(): SurfaceScopeAttributes {
    return mergeSurfaceScopeAttributes(
      this.parent?.attributes ?? [],
      [...this.local].map(([name, value]) => ({ name, value })),
    );
  }

  adopt(attributes: SurfaceScopeAttributes): void {
    for (const attribute of attributes) {
      this.local.set(attribute.name, attribute.value);
    }
  }

  stamp(root: ParentNode | Element | null | undefined): void {
    stampSurfaceScope(root, this.attributes);
  }
}

export function createSurfaceScopeRelay(
  parent?: SurfaceScopeRelay,
): SurfaceScopeRelay {
  return new SurfaceScopeRelay(parent);
}

export function isSurfaceScopeAttribute(name: string): boolean {
  return SCOPED_CSS_ATTRIBUTE.test(name);
}

export function surfaceScopeAttributesForElement(
  element: Element,
): SurfaceScopeAttributes {
  return [...element.attributes]
    .filter((attribute) => isSurfaceScopeAttribute(attribute.name))
    .map((attribute) => ({
      name: attribute.name,
      value: attribute.value,
    }));
}

export function surfaceScopeAttributesForTree(
  element: Element,
): SurfaceScopeAttributes {
  const scopes: SurfaceScopeAttribute[] = [];
  let current: Element | null = element;
  while (current) {
    scopes.push(...surfaceScopeAttributesForElement(current));
    current = current.parentElement;
  }
  return mergeSurfaceScopeAttributes(scopes.reverse());
}

export function mergeSurfaceScopeAttributes(
  ...attributeSets: SurfaceScopeAttributes[]
): SurfaceScopeAttributes {
  const merged = new Map<string, string>();
  for (const attributes of attributeSets) {
    for (const attribute of attributes) {
      merged.set(attribute.name, attribute.value);
    }
  }
  return [...merged].map(([name, value]) => ({ name, value }));
}

export function stampSurfaceScope(
  root: ParentNode | Element | null | undefined,
  attributes: SurfaceScopeAttributes,
): void {
  if (!root || attributes.length === 0) return;
  if (isElement(root)) {
    stampElement(root, attributes);
  }
  for (const element of root.querySelectorAll?.('*') ?? []) {
    stampElement(element, attributes);
  }
}

function isElement(value: unknown): value is Element {
  return !!(
    value &&
    typeof value === 'object' &&
    'nodeType' in value &&
    (value as Node).nodeType === 1
  );
}

function stampElement(
  element: Element,
  attributes: SurfaceScopeAttributes,
): void {
  for (const attribute of attributes) {
    if (element.getAttribute(attribute.name) !== attribute.value) {
      element.setAttribute(attribute.name, attribute.value);
    }
  }
}
