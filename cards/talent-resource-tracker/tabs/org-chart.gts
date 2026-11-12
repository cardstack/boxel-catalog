import GlimmerComponent from '@glimmer/component';
import { LoadingState } from '@cardstack/pretui/components/loading-state';
import { TrackerSection, TrackerEmpty, TrackerPage } from '../shared';
import { OrgTree, type OrgTreeItem } from '../org-tree';
import {
  buildTree as buildOrgTree,
  type TreeNode as OrgNode,
} from '@cardstack/catalog/utils/build-tree';
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
    <TrackerPage
      @group='People'
      @title='Org Chart'
      @subtitle='Reporting lines, current headcount'
    >
      <TrackerSection
        @title='Reporting lines'
        @meta={{this.panelMeta}}
        @padded={{true}}
      >
        {{#if this.orgRoots.length}}
          <OrgTree @roots={{this.orgRoots}} @onSelect={{@tracker.openCard}} />
        {{else if @tracker.isLoading}}
          <LoadingState @label='Loading' />
        {{else}}
          <TrackerEmpty>No reporting lines yet. Set a manager on employees in
            the Directory to build the chart.</TrackerEmpty>
        {{/if}}
      </TrackerSection>
    </TrackerPage>
  </template>
}
