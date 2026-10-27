import GlimmerComponent from '@glimmer/component';
import { PageScaffold } from '../../../ui-component/components/page-scaffold';
import { Panel } from '../../../ui-component/components/panel';
import { PanelHead } from '../shared';
import { OrgTree, type OrgTreeItem } from '../org-tree';
import {
  buildTree as buildOrgTree,
  type TreeNode as OrgNode,
} from '../../../utils/build-tree';
import { initialsOf } from '../../people/person-base';
import type { TrackerView } from '../talent-resource-tracker';

interface Signature {
  Args: {
    tracker: TrackerView;
  };
}

export class OrgChartTab extends GlimmerComponent<Signature> {
  get orgRoots(): OrgNode<OrgTreeItem>[] {
    let items = this.args.tracker.employees.map((e) => ({
      id: e.id,
      card: e,
      name: e.title,
      role: e.role,
      initials: initialsOf(e.name),
      photoUrl: e.photo?.resolvedUrl,
      status: e.status,
      managerId: e.manager?.id,
      openReqs: this.args.tracker.positions.filter(
        (p) => p.status === 'open' && p.hiringManager?.id === e.id,
      ).length,
    }));
    return buildOrgTree(items, (item) => item.managerId);
  }

  get panelMeta(): string {
    let n = this.args.tracker.employees.length;
    return this.args.tracker.isLoading
      ? '—'
      : `${n} ${n === 1 ? 'person' : 'people'}`;
  }

  <template>
    <PageScaffold
      @title='Org Chart'
      @subtitle='Reporting lines, current headcount'
    >
      <Panel>
        <:header><PanelHead
            @title='Reporting lines'
            @meta={{this.panelMeta}}
          /></:header>
        <:default>
          <OrgTree @roots={{this.orgRoots}} @onSelect={{@tracker.openCard}} />
        </:default>
      </Panel>
    </PageScaffold>
  </template>
}
