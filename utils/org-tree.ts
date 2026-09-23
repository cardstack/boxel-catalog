// A parent/child tree over any records, built once from a flat list.

export interface OrgNode<T> {
  item: T;
  children: OrgNode<T>[];
}

// Builds a forest from a flat list using a manager edge; cycle-safe.
export function buildOrgTree<T extends { id?: string }>(
  items: T[],
  managerIdOf: (item: T) => string | undefined,
): OrgNode<T>[] {
  let nodes = new Map<string, OrgNode<T>>();
  let list = items.filter((item) => item?.id);
  for (let item of list) {
    nodes.set(item.id!, { item, children: [] });
  }
  let roots: OrgNode<T>[] = [];
  for (let item of list) {
    let node = nodes.get(item.id!)!;
    let managerId = managerIdOf(item);
    let parent = managerId ? nodes.get(managerId) : undefined;
    if (parent && parent !== node && !isDescendant(node, parent)) {
      parent.children.push(node);
    } else {
      roots.push(node);
    }
  }
  return roots;
}

function isDescendant<T>(
  candidateAncestor: OrgNode<T>,
  node: OrgNode<T>,
): boolean {
  for (let child of candidateAncestor.children) {
    if (child === node || isDescendant(child, node)) {
      return true;
    }
  }
  return false;
}
