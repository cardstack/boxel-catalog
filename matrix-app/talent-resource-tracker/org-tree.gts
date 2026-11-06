import GlimmerComponent from '@glimmer/component';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import type { CardDef } from '@cardstack/base/card-api';
import { getComponent, StatusDot } from './shared';

import { Tree, type TreeNode } from '@cardstack/catalog/components/tree';

export interface OrgTreeItem {
  id?: string;
  name?: string;
  role?: string;
  photoUrl?: string;
  /** the person's card, shown as its own atom */
  card?: CardDef;
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

function openReqLabel(n: number): string {
  return `${n} Open Req${n === 1 ? '' : 's'}`;
}

const isActive = (status: string) => status === 'active';
const isOnboarding = (status: string) => status === 'onboarding';

function statusLabel(status: string): string {
  return status.charAt(0).toUpperCase() + status.slice(1);
}

/**
 * The reporting tree: one node per person (their atom, role) hanging off its
 * manager's guide line. A node carries the person's open requisitions as
 * hiring manager, and their status when it is anything but active.
 */
export class OrgTree extends GlimmerComponent<Signature> {
  select = (item: OrgTreeItem) => {
    this.args.onSelect?.({ id: item.id });
  };

  <template>
    <nav class='org-tree' aria-label='Reporting lines' ...attributes>
      <Tree @roots={{@roots}} @emptyMessage='No employees yet.'>
        <:row as |item|>
          <button
            type='button'
            class='org-node'
            aria-label={{item.name}}
            {{on 'click' (fn this.select item)}}
          >
            {{#let (getComponent item.card) as |Atom|}}{{#if Atom}}<Atom
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}<strong>{{item.name}}</strong>{{/if}}{{/let}}
            <span class='org-role'>{{item.role}}</span>
            {{#if item.openReqs}}
              <StatusDot
                @tone='primary'
                @label={{openReqLabel item.openReqs}}
              />
            {{/if}}
            {{#if item.status}}
              {{#unless (isActive item.status)}}
                <StatusDot
                  @tone={{if (isOnboarding item.status) 'warning' 'neutral'}}
                  @label={{statusLabel item.status}}
                />
              {{/unless}}
            {{/if}}
          </button>
        </:row>
      </Tree>
    </nav>
    <style scoped>
      /* The guide sits under the atom's 20px mark; each level steps in by
         that much plus a gap. Rows are flat 28px lines, no inner cards. */
      .org-tree {
        --tree-guide-x: calc(var(--trt-px) + 0.625rem);
        --tree-indent: calc(var(--tree-guide-x) + var(--boxel-sp-lg));
        --tree-row-pad: 0;
      }
      .org-node {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        min-height: var(--trt-rowh);
        max-inline-size: 100%;
        padding: 0 var(--trt-px);
        border: 0;
        background: none;
        color: inherit;
        font: inherit;
        text-align: left;
        cursor: pointer;
      }
      .org-node:hover {
        background: var(--hover);
      }
      .org-node:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: -0.125rem;
      }
      .org-role {
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        color: var(--muted-foreground);
      }
    </style>
  </template>
}
