import {
  CardDef,
  Component,
  containsMany,
  field,
  getComponent,
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
import { identifyCard, moduleFrom } from '@cardstack/runtime-common';
import {
  FilterChips,
  type FilterChipOption,
} from '@cardstack/pretui/components/filter-chips';

import StatusField from '../fields/status/status';
import PriorityField from '../fields/priority/priority';
import DueDateField from '../fields/due-date/due-date';
import CreatedAtField from '../fields/created-at/created-at';
import { StatePill, STATE_HUES } from '../components/state-pill';
import { GoldSpecCardGroup } from './gold-spec-card-group';
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
];

/** The catalog root, which every block `path` is relative to. */
const catalogRoot = new URL('../', here).href;
const CATALOG_PREFIX = '@cardstack/catalog/';
const SOURCE_EXTENSION = /\.g?ts$/;

/** A card's source file relative to the catalog root, read off its own class. */
function cardPath(card: CardDef): string {
  let ref = identifyCard(card.constructor as typeof CardDef);
  if (!ref) {
    return '';
  }
  let module = moduleFrom(ref);
  let path = module.startsWith(catalogRoot)
    ? module.slice(catalogRoot.length)
    : module.startsWith(CATALOG_PREFIX)
      ? module.slice(CATALOG_PREFIX.length)
      : module;
  return SOURCE_EXTENSION.test(path) ? path : `${path}.gts`;
}

/** A card section: the block entry plus the linked example it renders. */
interface CardBlock extends Block {
  card: CardDef;
}

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
    return new URL(this.args.path, catalogRoot).href;
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

/**
 * One linked card in every format: fitted at the badge, strip, tile and card
 * sizes, then embedded and atom, then isolated behind a disclosure. The card
 * is a shared example, so this only renders it.
 */
class CardFormats extends GlimmerComponent<{
  Args: { card: CardDef };
}> {
  get Card(): BoxComponent {
    return getComponent(this.args.card);
  }
  <template>
    <div class='fits'>
      <figure class='fit fit-badge'>
        <div class='fit-box'><this.Card @format='fitted' /></div>
        <figcaption>Fitted badge, 150 × 65</figcaption>
      </figure>
      <figure class='fit fit-strip'>
        <div class='fit-box'><this.Card @format='fitted' /></div>
        <figcaption>Fitted strip, 250 × 65</figcaption>
      </figure>
      <figure class='fit fit-tile'>
        <div class='fit-box'><this.Card @format='fitted' /></div>
        <figcaption>Fitted tile, 180 × 170</figcaption>
      </figure>
      <figure class='fit fit-card'>
        <div class='fit-box'><this.Card @format='fitted' /></div>
        <figcaption>Fitted card, 400 × 170</figcaption>
      </figure>
    </div>
    <div class='flows'>
      <div class='embedded'><this.Card @format='embedded' /></div>
      <span class='atom'><this.Card @format='atom' /></span>
    </div>
    <details class='isolated'>
      <summary>Isolated</summary>
      <this.Card @format='isolated' />
    </details>
    <style scoped>
      .fits {
        display: flex;
        flex-wrap: wrap;
        align-items: flex-start;
        gap: var(--boxel-sp-sm);
      }
      .fit {
        display: grid;
        gap: var(--boxel-sp-5xs);
        margin: 0;
      }
      .fit-box {
        overflow: hidden;
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius-sm);
      }
      .fit-badge .fit-box {
        width: 9.375rem;
        height: 4.0625rem;
      }
      .fit-strip .fit-box {
        width: 15.625rem;
        height: 4.0625rem;
      }
      .fit-tile .fit-box {
        width: 11.25rem;
        height: 10.625rem;
      }
      .fit-card .fit-box {
        width: 25rem;
        height: 10.625rem;
      }
      figcaption,
      summary {
        font-size: var(--boxel-caption-font-size);
        line-height: var(--boxel-caption-line-height);
        color: var(--muted-foreground);
      }
      .flows {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp);
      }
      .embedded {
        flex: 1 1 22rem;
        max-width: 36rem;
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius-sm);
      }
      summary {
        cursor: pointer;
      }
      .isolated[open] > summary {
        margin-block-end: var(--boxel-sp-xs);
      }
    </style>
  </template>
}

class GoldSpecDemoIsolated extends Component<typeof GoldSpecDemo> {
  hues = STATE_HUES;
  block = blockOf;
  @tracked active: string = BLOCKS[0]!.id;
  // The card cluster the sidebar and the card sections show; page state only.
  @tracked chosenGroup: string | undefined;

  get cardGroups(): GoldSpecCardGroup[] {
    return (this.args.model.cardGroups ?? []).filter(Boolean);
  }

  get groupOptions(): FilterChipOption[] {
    return this.cardGroups.map((g) => ({
      value: g.cardTitle,
      label: g.cardTitle,
      count: (g.cards ?? []).filter(Boolean).length,
    }));
  }

  get selectedGroup(): GoldSpecCardGroup | undefined {
    return (
      this.cardGroups.find((g) => g.cardTitle === this.chosenGroup) ??
      this.cardGroups[0]
    );
  }

  get cardBlocks(): CardBlock[] {
    let cards = (this.selectedGroup?.cards ?? []).filter(Boolean);
    return cards.map((card, i) => ({
      id: `card-${i}`,
      label: (card.constructor as typeof CardDef).displayName,
      kind: 'card',
      path: cardPath(card),
      card,
    }));
  }

  chooseGroup = (title: string) => {
    this.chosenGroup = title;
  };

  get groups(): {
    kind: BlockKind;
    label: string;
    sections: NavSection[];
  }[] {
    return GROUPS.map((g) => ({
      kind: g.kind,
      label: g.label,
      sections: (g.kind === 'card'
        ? this.cardBlocks
        : BLOCKS.filter((b) => b.kind === g.kind)
      ).map((b) => ({ id: b.id, label: b.label })),
    })).filter(
      (g) =>
        g.sections.length > 0 ||
        (g.kind === 'card' && this.cardGroups.length > 0),
    );
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
        <p>Every block in every state. Field rows show the embedded format, then
          the atom format. Cards come in clusters: pick one under Cards to see
          an example of each of its cards fitted at four sizes, embedded, atom
          and isolated.</p>
      </header>

      <div class='layout'>
        <aside class='sidebar' aria-label='Building blocks'>
          {{#each this.groups as |group|}}
            <div class='nav-group'>
              <span class='group-label'>{{group.label}}</span>
              {{#if (eq group.kind 'card')}}
                <FilterChips
                  class='cluster-filter'
                  @label='Card cluster'
                  @options={{this.groupOptions}}
                  @value={{this.selectedGroup.cardTitle}}
                  @onValueChange={{this.chooseGroup}}
                />
              {{/if}}
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

          {{#each this.cardBlocks as |entry|}}
            <section
              class='block {{if (eq this.active entry.id) "is-active"}}'
              data-sect={{entry.id}}
              aria-labelledby='{{entry.id}}-heading'
            >
              <BlockHead @entry={{entry}} @context={{@context}} />
              <p class='hint'>{{this.selectedGroup.cardTitle}}
                example:
                {{entry.card.cardTitle}}</p>
              <CardFormats @card={{entry.card}} />
            </section>
          {{/each}}
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
      /* Pret UI FilterChips: the count reads --ink-3, a fixed grey with no
         contrast guarantee, so it takes the muted ink instead. */
      .cluster-filter {
        --ink-3: var(--muted-foreground);
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
 * Created At across each relative-time unit, StatePill across every hue and
 * mode, and each linked card cluster (a Gold Spec Card Group) over its cards'
 * own examples. Each value renders in every format so a visual regression in
 * any block shows up side by side. A sidebar groups the blocks by kind, picks
 * the card cluster, and jumps to each section.
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
  // One linked group per card cluster; each links its cards' own examples.
  @field cardGroups = linksToMany(GoldSpecCardGroup);

  static isolated = GoldSpecDemoIsolated;
}

export default GoldSpecDemo;
