import GlimmerComponent from '@glimmer/component';
import { array } from '@ember/helper';
import type { CardDef } from '@cardstack/base/card-api';

import { Chip } from '../../ui-component/components/chip';

import { CardTiles } from './card-tiles';
import { Tree, type TreeNode, type TreeRowMeta } from '../../components/tree';

export interface OrgTreeItem {
  card?: CardDef;
  id?: string;
  name?: string;
  role?: string;
  initials?: string;
  photoUrl?: string;
  status?: string;
  openReqs?: number;
}

interface Signature {
  Args: {
    roots: TreeNode<OrgTreeItem>[];
    onSelect?: (item: OrgTreeItem) => void;
  };
  Element: HTMLElement;
}

/**
 * The reporting tree, on the catalog Tree. Each manager row rolls up its whole
 * team and the open requisitions under it, which is why this is a hiring view
 * rather than an org poster: a manager whose team is about to double is the
 * one whose interview load is full.
 */
export class OrgTree extends GlimmerComponent<Signature> {
  get openReqRollups(): Map<string, number> {
    let map = new Map<string, number>();
    let walk = (node: TreeNode<OrgTreeItem>): number => {
      let total =
        (node.item.openReqs ?? 0) +
        node.children.reduce((sum, child) => sum + walk(child), 0);
      if (node.item.id) map.set(node.item.id, total);
      return total;
    };
    (this.args.roots ?? []).forEach(walk);
    return map;
  }

  openReqsFor = (item: OrgTreeItem): number =>
    this.openReqRollups.get(item.id ?? '') ?? item.openReqs ?? 0;

  selectCard = (card: CardDef) => {
    this.args.onSelect?.({ id: card.id });
  };

  <template>
    <nav class='org-tree' aria-label='Reporting lines' ...attributes>
      <Tree @roots={{@roots}} @emptyMessage='No employees yet.'>
        <:row as |item meta|>
          <div class='org-row'>
            {{#if item.card}}
              <div class='org-card'>
                <CardTiles
                  @cards={{array item.card}}
                  @size='single-strip'
                  @list={{true}}
                  @onOpen={{this.selectCard}}
                />
              </div>
            {{/if}}
            <OrgRollup @meta={{meta}} @openReqs={{this.openReqsFor item}} />
          </div>
        </:row>
      </Tree>
    </nav>
    <style scoped>
      .org-row {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-sm);
        min-width: 0;
      }
      .org-card {
        flex: 1;
        min-width: 0;
        max-width: 26rem;
      }
    </style>
  </template>
}

interface RollupSignature {
  Args: { meta: TreeRowMeta; openReqs: number };
}

class OrgRollup extends GlimmerComponent<RollupSignature> {
  <template>
    <span class='rollup'>
      {{#if @meta.hasChildren}}
        <Chip @dot={{false}}>Team {{@meta.descendantCount}}</Chip>
      {{/if}}
      {{#if @openReqs}}
        <Chip @hue='var(--primary)'>Hiring {{@openReqs}}</Chip>
      {{/if}}
    </span>
    <style scoped>
      .rollup {
        display: inline-flex;
        gap: var(--boxel-sp-4xs);
        margin-inline-start: auto;
      }
    </style>
  </template>
}
