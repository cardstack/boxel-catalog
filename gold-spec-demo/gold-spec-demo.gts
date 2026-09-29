import {
  CardDef,
  Component,
  containsMany,
  field,
  type BoxComponent,
} from 'https://cardstack.com/base/card-api';
import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { eq } from '@cardstack/boxel-ui/helpers';
import LayoutGridIcon from '@cardstack/boxel-icons/layout-grid';

import StatusField from '../fields/status/status';
import PriorityField from '../fields/priority/priority';
import DueDateField from '../fields/due-date/due-date';
import CreatedAtField from '../fields/created-at/created-at';
import { StatePill, STATE_HUES } from '../components/state-pill';
import {
  EditSectionNav,
  type NavSection,
} from '../components/edit-section-nav';
import {
  BlockHead,
  DemoShell,
  scrollToSection,
  type Block,
  type BlockKind,
} from './demo-parts';

const DAY = 86400000;

/** Due dates relative to today, one per dueness band. */
function dueSamples(): Date[] {
  let now = new Date();
  let today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  return [-3, -1, 0, 1, 3, 30, 400].map(
    (days) => new Date(today.getTime() + days * DAY),
  );
}

/** Creation stamps relative to now, one per relative-time unit. */
function createdSamples(): Date[] {
  let now = Date.now();
  return [
    10 * 1000,
    5 * 60 * 1000,
    2 * 3600 * 1000,
    3 * DAY,
    16 * DAY,
    65 * DAY,
    400 * DAY,
  ].map((ago) => new Date(now - ago));
}

/**
 * The one list of blocks on this page: it drives the sidebar groups, each
 * section's heading and its source link, so nothing is listed twice.
 */
const BLOCKS: Block[] = [
  {
    id: 'status',
    label: 'Status',
    kind: 'field',
    path: 'fields/status/status.gts',
  },
  {
    id: 'priority',
    label: 'Priority',
    kind: 'field',
    path: 'fields/priority/priority.gts',
  },
  {
    id: 'due-date',
    label: 'Due Date',
    kind: 'field',
    path: 'fields/due-date/due-date.gts',
  },
  {
    id: 'created-at',
    label: 'Created At',
    kind: 'field',
    path: 'fields/created-at/created-at.gts',
  },
  {
    id: 'state-pill',
    label: 'StatePill',
    kind: 'component',
    path: 'components/state-pill.gts',
  },
];

/** Sidebar groups, in order; a group with no blocks is not shown. */
const GROUPS: { kind: BlockKind; label: string }[] = [
  { kind: 'field', label: 'Fields' },
  { kind: 'component', label: 'Components' },
];

function blockOf(id: string): Block {
  let block = BLOCKS.find((b) => b.id === id);
  if (!block) {
    throw new Error(`No block with id "${id}" in BLOCKS`);
  }
  return block;
}

/** One row per value: the embedded format beside the atom format. */
class FormatRows extends GlimmerComponent<{
  Args: { items: BoxComponent[] };
}> {
  <template>
    <table class='states'>
      <thead>
        <tr><th scope='col'>Embedded</th><th scope='col'>Atom</th></tr>
      </thead>
      <tbody>
        {{#each @items as |Item|}}
          <tr>
            <td><Item /></td>
            <td><Item @format='atom' /></td>
          </tr>
        {{/each}}
      </tbody>
    </table>
  </template>
}

class GoldSpecDemoIsolated extends Component<typeof GoldSpecDemo> {
  hues = STATE_HUES;
  block = blockOf;
  @tracked active: string = BLOCKS[0]!.id;
  get groups(): { label: string; sections: NavSection[] }[] {
    return GROUPS.map((g) => ({
      label: g.label,
      sections: BLOCKS.filter((b) => b.kind === g.kind).map((b) => ({
        id: b.id,
        label: b.label,
      })),
    })).filter((g) => g.sections.length > 0);
  }

  goTo = (id: string, event: Event) => {
    this.active = id;
    scrollToSection(id, event);
  };

  <template>
    <DemoShell
      @eyebrow='Preview only'
      @title='Gold Spec Demo'
      @intro='Every field and component in every state. Field rows show the embedded format, then the atom format. Cards have their own page per cluster: open a Gold Spec Card Group, such as CRM.'
    >
      <:nav>
        {{#each this.groups as |group|}}
          <div class='nav-group'>
            <span class='group-label'>{{group.label}}</span>
            <EditSectionNav
              @sections={{group.sections}}
              @activeId={{this.active}}
              @onSelect={{this.goTo}}
              @ariaLabel={{group.label}}
            />
          </div>
        {{/each}}
      </:nav>
      <:default>
        <section
          class='block {{if (eq this.active "status") "is-active"}}'
          data-sect='status'
          aria-labelledby='status-heading'
        >
          <BlockHead @entry={{this.block 'status'}} @context={{@context}} />
          <FormatRows @items={{@fields.statuses}} />
        </section>

        <section
          class='block {{if (eq this.active "priority") "is-active"}}'
          data-sect='priority'
          aria-labelledby='priority-heading'
        >
          <BlockHead @entry={{this.block 'priority'}} @context={{@context}} />
          <FormatRows @items={{@fields.priorities}} />
        </section>

        <section
          class='block {{if (eq this.active "due-date") "is-active"}}'
          data-sect='due-date'
          aria-labelledby='due-date-heading'
        >
          <BlockHead @entry={{this.block 'due-date'}} @context={{@context}} />
          <p class='hint'>Relative to today: overdue, yesterday, today,
            tomorrow, soon, later, next year.</p>
          <FormatRows @items={{@fields.dueDates}} />
        </section>

        <section
          class='block {{if (eq this.active "created-at") "is-active"}}'
          data-sect='created-at'
          aria-labelledby='created-at-heading'
        >
          <BlockHead @entry={{this.block 'created-at'}} @context={{@context}} />
          <p class='hint'>Relative to now: seconds, minutes, hours, days, weeks,
            months, years.</p>
          <FormatRows @items={{@fields.createdStamps}} />
        </section>

        <section
          class='block {{if (eq this.active "state-pill") "is-active"}}'
          data-sect='state-pill'
          aria-labelledby='state-pill-heading'
        >
          <BlockHead @entry={{this.block 'state-pill'}} @context={{@context}} />
          <p class='hint'>Every hue in each mode: tinted, with dot, emphatic,
            chrome.</p>
          <table class='states'>
            <thead>
              <tr>
                <th scope='col'>Hue</th>
                <th scope='col'>Tinted</th>
                <th scope='col'>Dot</th>
                <th scope='col'>Emphatic</th>
                <th scope='col'>Chrome</th>
              </tr>
            </thead>
            <tbody>
              {{#each this.hues as |hue|}}
                <tr>
                  <th scope='row'><code>{{hue}}</code></th>
                  <td><StatePill @label='In review' @hue={{hue}} /></td>
                  <td><StatePill
                      @label='In review'
                      @hue={{hue}}
                      @dot={{true}}
                    /></td>
                  <td><StatePill
                      @label='In review'
                      @hue={{hue}}
                      @emphatic={{true}}
                    /></td>
                  <td><StatePill
                      @label='In review'
                      @hue={{hue}}
                      @chrome={{true}}
                    /></td>
                </tr>
              {{/each}}
            </tbody>
          </table>
        </section>

      </:default>
    </DemoShell>

    <style scoped>
      .states {
        width: 100%;
        border-collapse: collapse;
      }
      .states th {
        text-align: start;
        font-family: var(--boxel-ui-label-font-family);
        font-size: var(--boxel-ui-label-font-size);
        font-weight: var(--boxel-ui-label-font-weight);
        line-height: var(--boxel-ui-label-line-height);
        letter-spacing: var(--boxel-ui-label-letter-spacing);
        color: var(--muted-foreground);
      }
      .states th,
      .states td {
        padding: var(--boxel-sp-2xs) var(--boxel-sp-xs);
        border-bottom: 1px solid var(--border);
        vertical-align: middle;
      }
      .states tbody tr:last-child > * {
        border-bottom: none;
      }
      .states code {
        font-family: var(--font-mono);
      }
    </style>
  </template>
}

/**
 * Preview of the gold-Spec building blocks, every state on one page: Status and
 * Priority across their full option sets, Due Date across each dueness band,
 * Created At across each relative-time unit, StatePill across every hue and
 * mode. Each value renders in every format so a visual regression in any block
 * shows up side by side. A sidebar groups the blocks by kind and jumps to each
 * section. Cards live on their own page per cluster (Gold Spec Card Group).
 */
export class GoldSpecDemo extends CardDef {
  static displayName = 'Gold Spec Demo';
  static icon = LayoutGridIcon;

  @field statuses = containsMany(StatusField);
  @field priorities = containsMany(PriorityField);
  @field dueDates = containsMany(DueDateField, {
    computeVia: dueSamples,
  });
  @field createdStamps = containsMany(CreatedAtField, {
    computeVia: createdSamples,
  });

  static isolated = GoldSpecDemoIsolated;
}

export default GoldSpecDemo;
