export interface SurfaceDomBindingCache {
  revision: number;
  elementLists: WeakMap<Element, Map<string, HTMLElement[]>>;
  rects: WeakMap<HTMLElement, DOMRect>;
}

export function createSurfaceDomBindingCache(
  revision = 0,
): SurfaceDomBindingCache {
  return {
    revision,
    elementLists: new WeakMap(),
    rects: new WeakMap(),
  };
}

export function cachedElementList(
  cache: SurfaceDomBindingCache | undefined,
  owner: Element,
  key: string,
  collect: () => HTMLElement[],
): HTMLElement[] {
  if (!cache) return collect();
  let lists = cache.elementLists.get(owner);
  if (!lists) {
    lists = new Map();
    cache.elementLists.set(owner, lists);
  }
  const cached = lists.get(key);
  if (cached) return cached;
  const collected = collect();
  lists.set(key, collected);
  return collected;
}

export function cachedRectForElement(
  element: HTMLElement,
  cache?: SurfaceDomBindingCache,
): DOMRect {
  const cached = cache?.rects.get(element);
  if (cached) return cached;
  const rect = element.getBoundingClientRect();
  cache?.rects.set(element, rect);
  return rect;
}
