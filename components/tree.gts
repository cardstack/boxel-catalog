import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import type { SafeString } from '@ember/template';
import type { CardDef } from '@cardstack/base/card-api';
import { IconButton } from '@cardstack/pretui/components/icon-button';

import { type TreeNode } from '../utils/build-tree';

/** The generic node shape; build one with buildTree. */
export type { TreeNode };

/** The forest builder, re-exported under the generic name. Cycle-safe. */
export { buildTree } from '../utils/build-tree';

export interface TreeRowMeta {
  depth: number;
  hasChildren: boolean;
  expanded: boolean;
  /** All descendants, not just direct children — "Team 4"-style rollups. */
  descendantCount: number;
}

interface RenderRow<T> {
  key: string;
  item: T;
  meta: TreeRowMeta;
  indent: SafeString;
}

interface Signature<T> {
  Args: {
    roots?: (TreeNode<T> | null | undefined)[];
    /** Start expanded (default) or collapsed. */
    defaultExpanded?: boolean;
    /** Show the expand/collapse carets (default). False lays every row out
     * fully expanded with no caret column. */
    collapsible?: boolean;
    /** Draw a vertical guide line down each ancestor's column, so a child
     * visibly hangs off its parent. */
    guides?: boolean;
    emptyMessage?: string;
  };
  Blocks: {
    /** Row content. Without it, CardDef items render as their atom. */
    row?: [T, TreeRowMeta];
  };
  Element: HTMLElement;
}

function countDescendants<T>(node: TreeNode<T>): number {
  return node.children.reduce(
    (sum, child) => sum + 1 + countDescendants(child),
    0,
  );
}

/**
 * The generic tree view: expand/collapse over any parent-child structure.
 * The block owns the mechanics every tree re-derives — carets, indentation,
 * per-node expansion that survives data refreshes (keyed by path, not object
 * identity), descendant rollup counts — and yields each row's content to the
 * consumer, because what a node LOOKS like is domain knowledge (an employee
 * with an avatar, a task with a status pill). Rendered flat from a DFS so
 * the row block works at every depth; visually nested via indentation.
 */
export class Tree<T> extends GlimmerComponent<Signature<T>> {
  @tracked toggledPaths: Set<string> = new Set();

  get defaultExpanded() {
    return this.args.defaultExpanded ?? true;
  }

  get collapsible() {
    return this.args.collapsible ?? true;
  }

  isExpanded(path: string): boolean {
    if (!this.collapsible) {
      return true;
    }
    return this.defaultExpanded !== this.toggledPaths.has(path);
  }

  get rows(): RenderRow<T>[] {
    let out: RenderRow<T>[] = [];
    let walk = (
      nodes: (TreeNode<T> | null | undefined)[],
      prefix: string,
      depth: number,
    ) => {
      nodes.filter(Boolean).forEach((node, index) => {
        let n = node as TreeNode<T>;
        let path = prefix ? `${prefix}.${index}` : String(index);
        let hasChildren = n.children.length > 0;
        let expanded = hasChildren && this.isExpanded(path);
        out.push({
          key: path,
          item: n.item,
          meta: {
            depth,
            hasChildren,
            expanded,
            descendantCount: countDescendants(n),
          },
          indent: htmlSafe(`--tree-depth: ${depth};`),
        });
        if (expanded) {
          walk(n.children, path, depth + 1);
        }
      });
    };
    walk(this.args.roots ?? [], '', 0);
    return out;
  }

  toggle = (path: string) => {
    let next = new Set(this.toggledPaths);
    if (next.has(path)) {
      next.delete(path);
    } else {
      next.add(path);
    }
    this.toggledPaths = next;
  };

  toggleRow = (row: RenderRow<T>) => this.toggle(row.key);

  cardComponent = (item: T) => {
    let ctor = (item as unknown as CardDef)?.constructor as
      | typeof CardDef
      | undefined;
    return ctor?.getComponent?.(item as unknown as CardDef);
  };

  <template>
    <ul
      class='tree'
      data-collapsible={{if this.collapsible 'true' 'false'}}
      data-guides={{if @guides 'true' 'false'}}
      ...attributes
    >
      {{#each this.rows key='key' as |row|}}
        <li class='tree-row' style={{row.indent}}>
          {{#if this.collapsible}}
            {{#if row.meta.hasChildren}}
              <IconButton
                @label={{if row.meta.expanded 'Collapse' 'Expand'}}
                @tone='neutral'
                @appearance='plain'
                @size='xs'
                class='caret {{if row.meta.expanded "open"}}'
                aria-expanded='{{if row.meta.expanded "true" "false"}}'
                {{on 'click' (fn this.toggleRow row)}}
              ><span
                  class='caret-glyph'
                  aria-hidden='true'
                >▸</span></IconButton>
            {{else}}
              <span class='caret-spacer'></span>
            {{/if}}
          {{/if}}
          <div class='tree-content'>
            {{#if (has-block 'row')}}
              {{yield row.item row.meta to='row'}}
            {{else}}
              {{#let (this.cardComponent row.item) as |C|}}
                {{#if C}}<C @format='atom' />{{/if}}
              {{/let}}
            {{/if}}
          </div>
        </li>
      {{else}}
        <li class='tree-empty'>{{if
            @emptyMessage
            @emptyMessage
            'Nothing here yet.'
          }}</li>
      {{/each}}
    </ul>
    <style scoped>
      /* Knobs: --tree-indent (per depth step), --tree-guide-x (where a
         guide sits inside its step; default the caret's centre) and
         --tree-row-pad (above and below each row). */
      .tree {
        --tree-caret: 1.5rem;
        margin: 0;
        padding: 0;
        color: var(--foreground);
      }
      .tree-row {
        list-style: none;
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-4xs);
        padding-block: var(--tree-row-pad, var(--boxel-sp-5xs));
        padding-inline-start: calc(
          var(--tree-depth, 0) * var(--tree-indent, 1.25rem)
        );
        border-radius: var(--boxel-border-radius-sm);
      }
      /* only a row with a caret acts as a row */
      .tree[data-collapsible='true'] .tree-row:hover {
        background-color: var(--muted);
      }
      /* One 1px rule per ancestor, painted across the indent: the gradient
         repeats once per depth step, so a row at depth 3 draws three. */
      .tree[data-guides='true'] .tree-row {
        --_tree-step: var(--tree-indent, 1.25rem);
        --_tree-x: var(--tree-guide-x, calc(var(--tree-caret) / 2));
        background-image: repeating-linear-gradient(
          to right,
          transparent 0 var(--_tree-x),
          var(--border-strong) var(--_tree-x) calc(var(--_tree-x) + 1px),
          transparent calc(var(--_tree-x) + 1px) var(--_tree-step)
        );
        background-size: calc(var(--tree-depth, 0) * var(--_tree-step)) 100%;
        background-repeat: no-repeat;
      }
      /* The caret and the spacer share one width, the minimum target size,
         so leaf rows line up with their expandable siblings. Only the glyph
         turns, so the button's focus ring stays square. */
      .caret {
        --pretui-button-h: var(--tree-caret);
        width: var(--tree-caret);
        flex: none;
        color: var(--muted-foreground);
      }
      .caret-glyph {
        display: inline-block;
        transition: transform 0.15s ease-out;
      }
      .caret.open .caret-glyph {
        transform: rotate(90deg);
      }
      .caret-spacer {
        width: var(--tree-caret);
        flex: none;
      }
      .tree-content {
        flex: 1;
        min-width: 0;
        display: flex;
        align-items: center;
      }
      .tree-empty {
        list-style: none;
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-sm);
      }
      @media (prefers-reduced-motion: reduce) {
        .caret-glyph {
          transition: none;
        }
      }
    </style>
  </template>
}

export default Tree;
