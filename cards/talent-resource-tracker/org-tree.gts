import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';

import { Avatar } from '@cardstack/pretui/components/avatar';
import { Button } from '@cardstack/pretui/components/button';
import { Chip } from '@cardstack/pretui/components/chip';

import {
  Tree,
  type TreeNode,
  type TreeRowMeta,
} from '../../components/tree';
import { stateColorOf } from '../../components/state-pill';
import { EMPLOYEE_STATUS_COLORS } from '../hr/employee';

export interface OrgTreeItem {
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

  hueFor = (item: OrgTreeItem): string =>
    stateColorOf(EMPLOYEE_STATUS_COLORS, item.status).ring;

  select = (item: OrgTreeItem) => {
    this.args.onSelect?.(item);
  };

  <template>
    <nav class='org-tree' aria-label='Reporting lines' ...attributes>
      <Tree @roots={{@roots}} @emptyMessage='No employees yet.'>
        <:row as |item meta|>
          <div class='org-row'>
            <Avatar
              @name={{if item.name item.name ''}}
              @src={{item.photoUrl}}
              @hue={{this.hueFor item}}
              @size={{28}}
            />
            <Button
              type='button'
              @tone='neutral'
              @appearance='plain'
              class='org-label'
              {{on 'click' (fn this.select item)}}
            >
              <span class='org-name'>{{item.name}}</span>
              <span class='org-role'>{{item.role}}</span>
            </Button>
            <OrgRollup
              @meta={{meta}}
              @openReqs={{this.openReqsFor item}}
            />
          </div>
        </:row>
      </Tree>
    </nav>
    <style scoped>
      .org-row {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        min-width: 0;
      }
      .org-label {
        display: flex;
        flex-direction: column;
        align-items: flex-start;
        min-width: 0;
        text-align: start;
      }
      .org-name {
        font-weight: 600;
        color: var(--foreground);
      }
      .org-role {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
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
