// A parent/child tree over any records, built once from a flat list.

export interface TreeNode<T> {
  item: T;
  children: TreeNode<T>[];
}

// Builds a forest from a flat list using a parent edge; cycle-safe.
export function buildTree<T extends { id?: string }>(
  items: T[],
  parentIdOf: (item: T) => string | undefined,
): TreeNode<T>[] {
  let nodes = new Map<string, TreeNode<T>>();
  let list = items.filter((item) => item?.id);
  for (let item of list) {
    nodes.set(item.id!, { item, children: [] });
  }
  let roots: TreeNode<T>[] = [];
  for (let item of list) {
    let node = nodes.get(item.id!)!;
    let parentId = parentIdOf(item);
    let parent = parentId ? nodes.get(parentId) : undefined;
    if (parent && parent !== node && !isDescendant(node, parent)) {
      parent.children.push(node);
    } else {
      roots.push(node);
    }
  }
  return roots;
}

function isDescendant<T>(
  candidateAncestor: TreeNode<T>,
  node: TreeNode<T>,
): boolean {
  for (let child of candidateAncestor.children) {
    if (child === node || isDescendant(child, node)) {
      return true;
    }
  }
  return false;
}
