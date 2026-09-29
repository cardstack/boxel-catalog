import {
  CardDef,
  Component,
  containsMany,
  field,
  linksToMany,
  type BoxComponent,
} from 'https://cardstack.com/base/card-api';
import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { Button } from '@cardstack/boxel-ui/components';
import { eq, not } from '@cardstack/boxel-ui/helpers';
import SwitchSubmodeCommand from '@cardstack/boxel-host/commands/switch-submode';
import type { CardContext } from 'https://cardstack.com/base/card-api';
import LayoutGridIcon from '@cardstack/boxel-icons/layout-grid';

import StatusField, { canTransition, statusHue } from '../fields/status/status';
import PriorityField, { priorityOption } from '../fields/priority/priority';
import DueDateField, { dueness } from '../fields/due-date/due-date';
import CreatedAtField from '../fields/created-at/created-at';
import { StatePill, STATE_HUES } from '../components/state-pill';
import { Table, type TableColumn } from '../components/table';
import { Board, type BoardColumn } from '../components/board';
import { TaskRecordExample } from '../fields/status/example/task-record-example';
import {
  EditSectionNav,
  type NavSection,
} from '../components/edit-section-nav';

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

// @ts-expect-error TS1470 -- import.meta is valid in realm-served modules; only the CommonJS type-check rejects it
const here: string = import.meta.url;

type BlockKind = 'field' | 'card' | 'component';

interface Block {
  id: string;
  label: string;
  kind: BlockKind;
  /** Source file, relative to the catalog root. */
  path: string;
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
  {
    id: 'table',
    label: 'Table',
    kind: 'component',
    path: 'components/table.gts',
  },
  {
    id: 'board',
    label: 'Board',
    kind: 'component',
    path: 'components/board.gts',
  },
];

// Table and Board run over the same task records the Table/Board Spec example
// uses, so the demo shows them on real cards rather than stand-in rows.
function task(item: CardDef): TaskRecordExample {
  return item as TaskRecordExample;
}

/** Severity stripe per due-date band; later dates carry no stripe. */
const DUE_STRIPE: Record<string, string> = {
  overdue: 'sev-over',
  today: 'sev-note',
  soon: 'sev-note',
};

/** Sidebar groups, in order; a group with no blocks is not shown. */
const GROUPS: { kind: BlockKind; label: string }[] = [
  { kind: 'field', label: 'Fields' },
  { kind: 'card', label: 'Cards' },
  { kind: 'component', label: 'Components' },
];

function blockOf(id: string): Block {
  let block = BLOCKS.find((b) => b.id === id);
  if (!block) {
    throw new Error(`No block with id "${id}" in BLOCKS`);
  }
  return block;
}

/** The block's file name; clicking opens it in code mode. */
class SourceLink extends GlimmerComponent<{
  Args: { path: string; context?: CardContext };
}> {
  get url() {
    return new URL(`../${this.args.path}`, here).href;
  }
  open = async () => {
    let commandContext = this.args.context?.commandContext;
    if (!commandContext) {
      return;
    }
    await new SwitchSubmodeCommand(commandContext).execute({
      submode: 'code',
      codePath: this.url,
    });
  };
  <template>
    <Button
      class='source-link'
      @kind='text-only'
      @size='extra-small'
      @disabled={{not @context.commandContext}}
      title='Open {{@path}} in code mode'
      {{on 'click' this.open}}
    ><code>{{@path}}</code></Button>
    <style scoped>
      .source-link code {
        font-family: var(--font-mono);
        font-size: var(--boxel-caption-font-size);
      }
    </style>
  </template>
}

/** A section's heading row: the block's name and its source link. */
class BlockHead extends GlimmerComponent<{
  Args: { entry: Block; context?: CardContext };
}> {
  <template>
    <div class='block-head'>
      <h2 id='{{@entry.id}}-heading'>{{@entry.label}}</h2>
      <SourceLink @path={{@entry.path}} @context={{@context}} />
    </div>
    <style scoped>
      .block-head {
        display: flex;
        flex-wrap: wrap;
        align-items: baseline;
        justify-content: space-between;
        gap: var(--boxel-sp-xs);
      }
    </style>
  </template>
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
  noItems: CardDef[] = [];

  columns: TableColumn[] = [
    { key: 'title', label: 'Task', value: (t) => task(t).title },
    { key: 'status', label: 'Status', sortValue: (t) => task(t).status },
    {
      key: 'priority',
      label: 'Priority',
      showAbove: 480,
      sortValue: (t) => task(t).priority,
    },
    {
      key: 'due',
      label: 'Due',
      showAbove: 640,
      value: (t) => task(t).dueDate?.toLocaleDateString(),
      sortValue: (t) => task(t).dueDate?.getTime(),
    },
  ];

  // Board columns come straight from the Status field's option set.
  boardColumns: BoardColumn[] = StatusField.statusOptions.map((o) => ({
    key: o.value,
    label: o.label ?? o.value,
  }));

  get items(): CardDef[] {
    return ((this.args.model.records ?? []) as CardDef[]).filter(Boolean);
  }

  rowClass = (item: CardDef) => {
    let band = dueness(task(item).dueDate);
    return band ? DUE_STRIPE[band] : undefined;
  };

  statusOf = (item: CardDef) => task(item).status;
  priorityOf = (item: CardDef) => task(item).priority;
  statusHueOf = (item: CardDef) => statusHue(StatusField, task(item).status);
  priorityHueOf = (item: CardDef) =>
    priorityOption(PriorityField, task(item).priority)?.hue;

  columnKeyFor = (item: CardDef) => task(item).status;

  // A move the Status transition graph does not allow snaps back.
  onMove = (item: CardDef, key: string) => {
    if (canTransition(StatusField, task(item).status, key)) {
      task(item).status = key;
    }
  };
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
    let root = (event.currentTarget as HTMLElement).closest('.showcase');
    root
      ?.querySelector(`[data-sect='${id}']`)
      ?.scrollIntoView({ block: 'start', behavior: 'smooth' });
  };

  <template>
    <article class='showcase'>
      <header class='intro'>
        <span class='eyebrow'>Preview only</span>
        <h1>Gold Spec Demo</h1>
        <p>Every block in every state. Each row shows the embedded format, then
          the atom format.</p>
      </header>

      <div class='layout'>
        <aside class='sidebar' aria-label='Building blocks'>
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
        </aside>

        <div class='blocks'>
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
            <BlockHead
              @entry={{this.block 'created-at'}}
              @context={{@context}}
            />
            <p class='hint'>Relative to now: seconds, minutes, hours, days,
              weeks, months, years.</p>
            <FormatRows @items={{@fields.createdStamps}} />
          </section>

          <section
            class='block {{if (eq this.active "state-pill") "is-active"}}'
            data-sect='state-pill'
            aria-labelledby='state-pill-heading'
          >
            <BlockHead
              @entry={{this.block 'state-pill'}}
              @context={{@context}}
            />
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

          <section
            class='block {{if (eq this.active "table") "is-active"}}'
            data-sect='table'
            aria-labelledby='table-heading'
          >
            <BlockHead @entry={{this.block 'table'}} @context={{@context}} />
            <p class='hint'>Paged five at a time through Pret UI Pagination,
              sortable headers, a severity stripe from each due date, then the
              empty state.</p>
            <Table
              @items={{this.items}}
              @columns={{this.columns}}
              @rowClass={{this.rowClass}}
              @pageSize={{5}}
              @caption='Tasks'
              @emptyMessage='No tasks linked'
            >
              <:cell as |item column|>
                {{#if (eq column.key 'status')}}
                  <StatePill
                    @label={{this.statusOf item}}
                    @hue={{this.statusHueOf item}}
                    @dot={{true}}
                  />
                {{else if (eq column.key 'priority')}}
                  <StatePill
                    @label={{this.priorityOf item}}
                    @hue={{this.priorityHueOf item}}
                  />
                {{/if}}
              </:cell>
            </Table>
            <Table
              @items={{this.noItems}}
              @columns={{this.columns}}
              @caption='Empty'
              @emptyMessage='No tasks match'
            />
          </section>

          <section
            class='block board-block
              {{if (eq this.active "board") "is-active"}}'
            data-sect='board'
            aria-labelledby='board-heading'
          >
            <BlockHead @entry={{this.block 'board'}} @context={{@context}} />
            <p class='hint'>Columns are the Status field's option set; a drag
              the transition graph does not allow snaps back.</p>
            <Board
              @boardLabel='Tasks'
              @items={{this.items}}
              @columns={{this.boardColumns}}
              @columnKeyFor={{this.columnKeyFor}}
              @onMove={{this.onMove}}
            />
          </section>
        </div>
      </div>
    </article>

    <style scoped>
      .showcase {
        container-type: inline-size;
        display: grid;
        gap: var(--boxel-sp-lg);
        padding: var(--boxel-sp-lg);
        max-width: 70rem;
        margin-inline: auto;
      }
      .intro {
        display: grid;
        gap: var(--boxel-sp-4xs);
      }
      .intro p,
      .hint {
        font-size: var(--boxel-caption-font-size);
        line-height: var(--boxel-caption-line-height);
        color: var(--muted-foreground);
      }
      .eyebrow,
      .group-label {
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .layout {
        display: grid;
        grid-template-columns: 11rem minmax(0, 1fr);
        align-items: start;
        gap: var(--boxel-sp-lg);
      }
      .sidebar {
        position: sticky;
        top: var(--boxel-sp);
        display: grid;
        gap: var(--boxel-sp);
      }
      .nav-group {
        display: grid;
        gap: var(--boxel-sp-2xs);
      }
      .blocks {
        display: grid;
        gap: var(--boxel-sp-lg);
      }
      .block {
        display: grid;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp);
        background-color: var(--card);
        color: var(--card-foreground);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        scroll-margin-top: var(--boxel-sp);
      }
      /* mirror the rail's active stop on the section itself */
      .board-block {
        min-height: 26.25rem;
        grid-template-rows: auto auto 1fr;
      }
      .block.is-active {
        box-shadow: 0 0 0 2px var(--ring);
      }
      .block :deep(.states) {
        width: 100%;
        border-collapse: collapse;
      }
      .block :deep(.states th) {
        text-align: start;
        font-family: var(--boxel-ui-label-font-family);
        font-size: var(--boxel-ui-label-font-size);
        font-weight: var(--boxel-ui-label-font-weight);
        line-height: var(--boxel-ui-label-line-height);
        letter-spacing: var(--boxel-ui-label-letter-spacing);
        color: var(--muted-foreground);
      }
      .block :deep(.states th),
      .block :deep(.states td) {
        padding: var(--boxel-sp-2xs) var(--boxel-sp-xs);
        border-bottom: 1px solid var(--border);
        vertical-align: middle;
      }
      .block :deep(.states tbody tr:last-child > *) {
        border-bottom: none;
      }
      .states code {
        font-family: var(--font-mono);
      }
      @container (width < 40rem) {
        .layout {
          grid-template-columns: minmax(0, 1fr);
        }
        .sidebar {
          position: static;
        }
      }
    </style>
  </template>
}

/**
 * Preview of the gold-Spec building blocks, every state on one page: Status and
 * Priority across their full option sets, Due Date across each dueness band,
 * Created At across each relative-time unit, and StatePill across every hue
 * and mode. Each value renders in embedded and atom so a visual regression in
 * any block shows up side by side. A sidebar groups the blocks by kind and
 * jumps to each section.
 */
export class GoldSpecDemo extends CardDef {
  static displayName = 'Gold Spec Demo';
  static icon = LayoutGridIcon;

  @field statuses = containsMany(StatusField);
  @field priorities = containsMany(PriorityField);
  @field dueDates = containsMany(DueDateField, {
    computeVia: dueSamples,
  });
  @field records = linksToMany(TaskRecordExample);
  @field createdStamps = containsMany(CreatedAtField, {
    computeVia: createdSamples,
  });

  static isolated = GoldSpecDemoIsolated;
}

export default GoldSpecDemo;
