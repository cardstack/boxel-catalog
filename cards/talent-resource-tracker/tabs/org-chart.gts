import GlimmerComponent from '@glimmer/component';
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

  <template>
    <section class='tab-section'>
      <div class='sec-head'>
        <div class='htext'>
          <h2>Org Chart</h2>
          <p class='byline'>Reporting lines, current headcount</p>
        </div>
      </div>
      <OrgTree @roots={{this.orgRoots}} @onSelect={{@tracker.openCard}} />
    </section>
    <style scoped>
      .rail-link.current {
        border-left-color: var(--primary);
      }
      .rail-link.current .t {
        color: var(--primary-ink);
        font-weight: 700;
      }
      .sec-head {
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp);
        padding-bottom: var(--boxel-sp);
        border-bottom: 2px solid var(--card-foreground);
        margin: 0 0 var(--boxel-sp-lg);
      }
      .sec-head .htext {
        margin-right: auto;
      }
      .sec-head .htext h2 {
        font-family: var(--font-sans);
        font-weight: 700;
        font-size: 20px;
        margin: 0 0 3px;
      }
      .sec-head .htext .byline {
        font-family: var(--font-mono);
        font-size: 11.5px;
        letter-spacing: 0.02em;
        color: var(--muted-foreground);
        margin: 0;
      }
      .tab-section {
        animation: tracker-tab-fade-in 0.2s ease-out;
      }
      @keyframes tracker-tab-fade-in {
        from {
          opacity: 0;
        }
        to {
          opacity: 1;
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .tab-section {
          animation: none;
        }
      }
      .tab-section > .directory.grid-view {
        --item-width: auto;
        --item-height: 14rem;
        grid-template-columns: repeat(auto-fill, minmax(13rem, 1fr));
      }
      .sec-head {
        flex: none;
      }
      @keyframes action-busy-pulse {
        0%,
        100% {
          opacity: 1;
        }
        50% {
          opacity: 0.55;
        }
      }
    </style>
  </template>
}
