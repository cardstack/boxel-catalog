import GlimmerComponent from '@glimmer/component';
import { fn } from '@ember/helper';
import { AVATAR_HUE } from '@cardstack/catalog/components/pretui-helpers';

import { Avatar } from '../../ui-component/components/avatar';
import { Card } from '../../ui-component/components/card';
import { Chip } from '../../ui-component/components/chip';
import { Item } from '../../ui-component/components/item';

import { Tree, type TreeNode } from '../../components/tree';

export interface OrgTreeItem {
  id?: string;
  name?: string;
  role?: string;
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

function openReqLabel(n: number): string {
  return `${n} Open Req${n === 1 ? '' : 's'}`;
}

const isActive = (status: string) => status === 'active';
const isOnboarding = (status: string) => status === 'onboarding';

function statusLabel(status: string): string {
  return status.charAt(0).toUpperCase() + status.slice(1);
}

/**
 * The reporting tree: one node per person (photo, name, role) hanging off its
 * manager's guide line. A node carries the person's open requisitions as
 * hiring manager, and their status when it is anything but active.
 */
export class OrgTree extends GlimmerComponent<Signature> {
  select = (item: OrgTreeItem) => {
    this.args.onSelect?.({ id: item.id });
  };

  <template>
    <nav class='org-tree' aria-label='Reporting lines' ...attributes>
      <Tree
        @roots={{@roots}}
        @collapsible={{false}}
        @guides={{true}}
        @emptyMessage='No employees yet.'
      >
        <:row as |item|>
          <Card
            class='org-node'
            @size='s'
            @interactive={{true}}
            @onSelect={{fn this.select item}}
            @selectLabel={{item.name}}
          >
            <Item @title={{item.name}} @size='xl'>
              <:leading>
                <Avatar
                  @name={{if item.name item.name '?'}}
                  @src={{item.photoUrl}}
                  @hue={{AVATAR_HUE}}
                  @size={{40}}
                  aria-hidden='true'
                />
              </:leading>
              <:description><span
                  class='org-role'
                >{{item.role}}</span></:description>
              <:trailing>
                {{#if item.openReqs}}
                  <Chip
                    @tone='primary'
                    @appearance='soft'
                    @shape='pill'
                    @dot={{false}}
                  >{{openReqLabel item.openReqs}}</Chip>
                {{/if}}
                {{#if item.status}}
                  {{#unless (isActive item.status)}}
                    <Chip
                      @tone={{if
                        (isOnboarding item.status)
                        'warning'
                        'neutral'
                      }}
                      @appearance='soft'
                      @shape='pill'
                      @dot={{false}}
                    >{{statusLabel item.status}}</Chip>
                  {{/unless}}
                {{/if}}
              </:trailing>
            </Item>
          </Card>
        </:row>
      </Tree>
    </nav>
    <style scoped>
      /* The guide sits under the avatar's centre, and each level steps in
         by that much plus a gap, so a child hangs off its parent's line. */
      .org-tree {
        --_org-avatar: 2.5rem;
        --tree-guide-x: calc(var(--boxel-sp-xs) + var(--_org-avatar) / 2);
        --tree-indent: calc(var(--tree-guide-x) + var(--boxel-sp-xl));
        --tree-row-pad: var(--boxel-sp-4xs);
        /* initials sit on the rail's colour, in the title navy */
        --pretui-avatar-bg: var(--sidebar);
        --pretui-avatar-fg: var(--primary-ink);
        --pretui-avatar-font-size: var(--boxel-font-size-xs);
      }
      .org-node {
        --pretui-card-pad: var(--boxel-sp-xs);
        --pretui-card-shadow: var(--shadow-sm);
        --pretui-card-radius: calc(
          var(--radius) - var(--boxel-border-radius-xs)
        );
        inline-size: 26rem;
        max-inline-size: 100%;
      }
      .org-role {
        display: block;
        font-size: var(--boxel-font-size-xs);
      }
    </style>
  </template>
}
