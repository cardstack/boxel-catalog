import type { TemplateOnlyComponent } from '@ember/component/template-only';
import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { modifier } from 'ember-modifier';
import { on } from '@ember/modifier';
import { hash } from '@ember/helper';
import type { ComponentLike } from '@glint/template';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Button } from '@cardstack/pretui/components/button';
import { IconButton } from '@cardstack/pretui/components/icon-button';
import { Menu } from '@cardstack/pretui/components/menu';
import { SearchInput } from '@cardstack/pretui/components/search-input';
import { FilterChips } from '@cardstack/pretui/components/filter-chips';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import {
  LayoutControl,
  type LayoutControlForm,
  type LayoutControlSlotSignature,
} from '@cardstack/pretui/components/layout-control';
import { iconFor } from '@cardstack/pretui/icon-registry';
import type { MenuEntry } from '@cardstack/pretui/components/menu';
import type { PageStat } from '@cardstack/pretui/components/page-scaffold';
import type { Candidate } from '../hr/candidate';
import { type BaseDef } from '@cardstack/base/card-api';
import { codeRef } from '@cardstack/runtime-common';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
export const here: string = import.meta.url;
export const employeeRef = codeRef(here, '../hr/employee', 'Employee');
export const meetingRef = codeRef(here, '../hr/meeting', 'Meeting');

// Renders a card instance fetched from a live query (which has no @fields
// entry to hand the template) via its own class's component.
export function getComponent(cardOrField: BaseDef | undefined) {
  if (!cardOrField) {
    return undefined;
  }
  return (cardOrField.constructor as typeof BaseDef).getComponent(cardOrField);
}

export const TABS = [
  'Dashboard',
  'Positions',
  'Applications',
  'Pipeline',
  'Offers',
  'Requisitions',
  'Onboarding',
  'Contractors',
  'PTO',
  'Reviews',
  'Directory',
  'Calendar',
  'Org Chart',
] as const;
export type Tab = (typeof TABS)[number];

export interface CandidateSnapshot {
  status: Candidate['status'];
  boardOrder: Candidate['boardOrder'];
  offerState: Candidate['offerState'];
}

export function snapshotCandidate(candidate: Candidate): CandidateSnapshot {
  return {
    status: candidate.status,
    boardOrder: candidate.boardOrder,
    offerState: candidate.offerState,
  };
}

export function restoreCandidate(
  candidate: Candidate,
  snapshot: CandidateSnapshot,
) {
  candidate.status = snapshot.status;
  candidate.boardOrder = snapshot.boardOrder;
  candidate.offerState = snapshot.offerState;
}

// Panel's <:header> for a list tab: the title, and its count muted at the
// end of the same row, as the mockup's panel heading has them.
export const PanelHead: TemplateOnlyComponent<{
  Args: { title: string; meta?: string };
}> = <template>
  <div class='panel-head'>
    <h2>{{@title}}</h2>
    {{#if @meta}}<span class='panel-meta'>{{@meta}}</span>{{/if}}
  </div>
  <style scoped>
    .panel-head {
      display: flex;
      flex-wrap: wrap;
      align-items: baseline;
      gap: var(--boxel-sp-xs);
    }
    h2 {
      margin: 0;
      font-family: var(--font-sans);
      font-size: var(--pretui-panel-title-size, var(--boxel-font-size-sm));
      font-weight: 800;
    }
    .panel-meta {
      font-size: var(--boxel-font-size-xs);
      color: var(--muted-foreground);
    }
  </style>
</template>;

// The mock's flat section (.card + .sh): one hairline card, a head of
// h2 12px 800 + muted meta + a right-aligned quiet link, rows flush below.
export const TrackerSection: TemplateOnlyComponent<{
  Args: { title: string; meta?: string; padded?: boolean; flat?: boolean };
  Blocks: { default: []; aside: [] };
  Element: HTMLElement;
}> = <template>
  <section class='ts' data-flat={{if @flat 'true'}} ...attributes>
    <div class='ts-head'>
      <h2>{{@title}}</h2>
      {{#if @meta}}<span class='ts-meta'>{{@meta}}</span>{{/if}}
      {{#if (has-block 'aside')}}<span class='ts-aside'>{{yield
            to='aside'
          }}</span>{{/if}}
    </div>
    <div class='ts-body' data-padded={{if @padded 'true'}}>{{yield}}</div>
  </section>
  <style scoped>
    .ts {
      min-width: 0;
      background: var(--card);
      color: var(--card-foreground);
      border: 1px solid var(--border);
      border-radius: var(--radius);
      overflow: hidden;
    }
    .ts[data-flat] {
      border: 0;
      border-radius: 0;
      background: none;
    }
    .ts-head {
      display: flex;
      align-items: baseline;
      gap: var(--boxel-sp-2xs);
      padding: var(--trt-py) var(--trt-px);
    }
    h2 {
      margin: 0;
      font-family: var(--font-sans);
      font-size: var(--trt-fs);
      font-weight: 800;
      line-height: 1.3;
    }
    .ts-meta {
      color: var(--muted-foreground);
      font-size: calc(var(--trt-fs) - 1px);
    }
    /* quiet text links: no control box, so the head keeps the mock's height */
    .ts-aside {
      margin-left: auto;
      --pretui-button-h: 0;
      --pretui-button-px: 0;
    }
    .ts-body[data-padded] {
      padding: 0 var(--trt-px) var(--boxel-sp-2xs);
    }
  </style>
</template>;

// Columns that drop by width (the mock's tables): measure the section, keep
// the first column and any `keep` keys, drop the rest from the end until
// every column has ~6rem.
export class ColumnFit {
  @tracked width = 0;
  measure = modifier((el: HTMLElement) => {
    let ro = new ResizeObserver(([e]) => {
      this.width = e?.contentRect.width ?? 0;
    });
    ro.observe(el);
    return () => ro.disconnect();
  });
  pick = (keys: string[], keep: string[] = ['status', 'action']): string[] => {
    if (!this.width) {
      return keys;
    }
    let max = Math.max(2, Math.floor(this.width / 96));
    let visible = [...keys];
    for (let i = visible.length - 1; visible.length > max && i > 0; i--) {
      if (!keep.includes(visible[i]!)) {
        visible.splice(i, 1);
      }
    }
    return visible;
  };
}

// An empty note inside a section: one muted line, no well, no rounding.
export const TrackerEmpty: TemplateOnlyComponent<{
  Blocks: { default: [] };
}> = <template>
  <p class='te'>{{yield}}</p>
  <style scoped>
    .te {
      margin: 0;
      padding: var(--trt-py) var(--trt-px);
      border-top: 1px solid var(--border);
      color: var(--muted-foreground);
      font-size: var(--trt-fs);
    }
  </style>
</template>;

// A "needs attention" line item that jumps to the tab holding the work:
// tone dot + bold text + arrow, no pill (rows of one alerts line).
export const AlertPill: TemplateOnlyComponent<{
  Args: { tone: 'warning' | 'danger'; onClick: () => void };
  Blocks: { default: [] };
}> = <template>
  <button type='button' class='alert-item' {{on 'click' @onClick}}><span
      class='alert-dot'
      data-tone={{@tone}}
      aria-hidden='true'
    ></span>{{yield}}<span
      class='alert-arrow'
      aria-hidden='true'
    >→</span></button>
  <style scoped>
    .alert-item {
      display: inline-flex;
      align-items: center;
      gap: var(--boxel-sp-4xs);
      margin: 0;
      padding: 0;
      border: 0;
      background: none;
      color: var(--foreground);
      font: inherit;
      font-weight: 600;
      cursor: pointer;
    }
    .alert-item:hover {
      text-decoration: underline;
    }
    .alert-item:focus-visible {
      outline: 2px solid var(--ring);
      outline-offset: 0.125rem;
    }
    .alert-arrow {
      color: var(--primary-ink);
    }
    .alert-dot {
      inline-size: 0.4375rem;
      block-size: 0.4375rem;
      border-radius: 50%;
      background: var(--warning);
    }
    .alert-dot[data-tone='danger'] {
      background: var(--destructive);
    }
  </style>
</template>;

// The first-cell text of a table row as a real button: the keyboard path for
// DataTable's @onRowActivate, which is a mouse shortcut only. It reads as
// plain text until hovered or focused.
export const RowOpen: TemplateOnlyComponent<{
  Args: { onOpen: () => void };
  Blocks: { default: [] };
}> = <template>
  <button type='button' class='row-open' {{on 'click' @onOpen}}>
    {{yield}}
  </button>
  <style scoped>
    .row-open {
      display: inline-flex;
      align-items: center;
      gap: inherit;
      margin: 0;
      padding: 0;
      border: 0;
      background: none;
      color: inherit;
      font: inherit;
      text-align: start;
      cursor: pointer;
    }
    .row-open:hover {
      color: var(--primary);
      text-decoration: underline;
    }
    .row-open:focus-visible {
      outline: 0.125rem solid var(--ring);
      outline-offset: 0.125rem;
      border-radius: var(--radius);
    }
  </style>
</template>;

// A status as dot + text (never a pill inside a row).
export const StatusDot: TemplateOnlyComponent<{
  Args: { tone?: string; label?: string };
}> = <template>
  <span class='status-dot' data-tone={{@tone}}><span
      class='dot'
      aria-hidden='true'
    ></span>{{@label}}</span>
  <style scoped>
    .status-dot {
      display: inline-flex;
      align-items: center;
      gap: var(--boxel-sp-4xs);
      font-weight: 600;
      white-space: nowrap;
    }
    .dot {
      inline-size: 0.4375rem;
      block-size: 0.4375rem;
      flex: none;
      border-radius: 50%;
      background: var(--muted-foreground);
    }
    [data-tone='success'] .dot {
      background: var(--success);
    }
    [data-tone='warning'] .dot {
      background: var(--warning);
    }
    [data-tone='danger'] .dot,
    [data-tone='destructive'] .dot {
      background: var(--destructive);
    }
    [data-tone='info'] .dot {
      background: var(--info);
    }
    [data-tone='primary'] .dot {
      background: var(--primary);
    }
  </style>
</template>;

// One height for every control in a tracker toolbar (the mock's Compact 26px).
export const CONTROL_HEIGHT = '1.625rem';

const F = (...forms: [string, number][]): LayoutControlForm[] =>
  forms.map(([name, minWidth]) => ({ name, minWidth }));
// rem widths, richest first (the mock's Directory toolbar table)
const ACTION_FORMS = F(['label', 8], ['icon', 1.75]);
const SEARCH_FORMS = F(['field', 15], ['field-s', 10.5], ['field-xs', 6]);
const VIEW_FORMS = F(['text', 7], ['menu', 0]);

type SlotComponent = ComponentLike<LayoutControlSlotSignature>;

interface TrackerActionSignature {
  Args: {
    slot: SlotComponent;
    id: string;
    label: string;
    icon?: string;
    /** 0 stays in the row longest */
    priority?: number;
    primary?: boolean;
    loading?: boolean;
    onClick: () => void;
  };
}

// A header / toolbar action as a LayoutControl slot: full label, then icon.
export class TrackerAction extends GlimmerComponent<TrackerActionSignature> {
  forms = ACTION_FORMS;
  get icon() {
    return iconFor(this.args.icon ?? 'plus');
  }
  <template>
    <@slot
      @id={{@id}}
      @priority={{if @priority @priority 0}}
      @forms={{this.forms}}
      as |form|
    >
      {{#if (eq form 'icon')}}
        <IconButton
          @label={{@label}}
          @icon={{this.icon}}
          @tone={{if @primary 'primary' 'neutral'}}
          @appearance={{if @primary 'accent' 'outlined'}}
          @loading={{@loading}}
          {{on 'click' @onClick}}
        />
      {{else}}
        {{! xs drops padding-block, so the bar's --control-height sets the height }}
        <Button
          type='button'
          @size='xs'
          @tone={{if @primary 'primary' 'neutral'}}
          @appearance={{if @primary 'accent' 'outlined'}}
          @loading={{@loading}}
          @icon={{this.icon}}
          {{on 'click' @onClick}}
        >{{@label}}</Button>
      {{/if}}
    </@slot>
  </template>
}

export interface TrackerBar {
  Slot: SlotComponent;
  Action: ComponentLike<{
    Args: Omit<TrackerActionSignature['Args'], 'slot'>;
  }>;
}

// A stat card: the kit PageStat plus the mock's 7px dot, given as a tone.
export type TrackerStat = PageStat & {
  dot?: 'success' | 'info' | 'warning' | 'destructive' | 'primary';
};

interface TrackerPageSignature {
  Args: {
    /** the rail group, shown in the eyebrow after the app name */
    group?: string;
    title: string;
    subtitle?: string;
    stats?: TrackerStat[];
  };
  Blocks: {
    /** header actions; yielded a LayoutControl so each picks a form by space */
    actions: [TrackerBar];
    alerts: [];
    default: [];
  };
}

// The page frame every tab shares (the compact mock's header): mono caps
// eyebrow, a short primary bar, the heading-font title, a muted subtitle,
// actions in a LayoutControl, flat stat cards, then the sections.
export class TrackerPage extends GlimmerComponent<TrackerPageSignature> {
  <template>
    <article class='tp'>
      <header class='tp-head'>
        <div class='tp-title'>
          <p class='tp-eyebrow'>Talent &amp; Resource Tracker{{#if @group}}
              ·
              {{@group}}{{/if}}</p>
          <span class='tp-bar' aria-hidden='true'></span>
          <h1>{{@title}}</h1>
        </div>
        {{#if (has-block 'actions')}}
          <LayoutControl
            class='tp-actions'
            @label='{{@title}} actions'
            @controlHeight={{CONTROL_HEIGHT}}
            as |lc|
          >
            {{yield
              (hash Slot=lc.Slot Action=(component TrackerAction slot=lc.Slot))
              to='actions'
            }}
          </LayoutControl>
        {{/if}}
      </header>
      {{#if @subtitle}}
        <p class='tp-sub' role='status'>{{@subtitle}}</p>
      {{/if}}
      {{yield to='alerts'}}
      {{#if @stats.length}}
        <ul class='tp-stats' aria-label='Summary'>
          {{#each @stats as |s|}}
            <li class='tp-stat'>
              <span class='tp-stat-label'>{{#if s.dot}}<span
                    class='tp-dot'
                    data-tone={{s.dot}}
                    aria-hidden='true'
                  ></span>{{/if}}{{s.label}}</span>
              <span class='tp-stat-value'>{{s.value}}</span>
              {{#if s.hint}}<span
                  class='tp-stat-note'
                  data-tone={{s.hintTone}}
                >{{s.hint}}</span>{{/if}}
            </li>
          {{/each}}
        </ul>
      {{/if}}
      {{yield}}
    </article>
    <style scoped>
      .tp {
        container-type: inline-size;
        height: 100%;
        overflow-y: auto;
        box-sizing: border-box;
        display: grid;
        grid-template-columns: minmax(0, 1fr);
        grid-auto-rows: max-content;
        align-content: start;
        gap: var(--trt-gap);
        padding: var(--trt-pad);
        font-size: var(--trt-fs);
      }
      .tp-head {
        display: flex;
        align-items: flex-end;
        gap: var(--trt-gap);
      }
      .tp-title {
        flex: 0 1 auto;
        min-width: 0;
      }
      .tp-eyebrow {
        margin: 0;
        font: 600 calc(var(--trt-fs) - 0.1875rem) / 1.3 var(--font-mono);
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--subtle-foreground);
      }
      .tp-bar {
        display: block;
        inline-size: 2.75rem;
        block-size: 0.1875rem;
        margin: var(--boxel-sp-3xs) 0 var(--boxel-sp-2xs);
        border-radius: var(--boxel-border-radius-xs);
        background: var(--primary);
      }
      h1 {
        margin: 0;
        /* only the page title takes the theme's heading face */
        font-family: var(--boxel-heading-font-family);
        font-weight: var(--boxel-heading-font-weight);
        letter-spacing: var(--boxel-heading-letter-spacing);
        text-transform: uppercase;
        font-size: 2.5rem;
        line-height: 1;
      }
      /* the bar takes the free width so it can choose its richest form */
      .tp-actions {
        flex: 1 1 0;
        min-width: 1.625rem;
        justify-content: flex-end;
      }
      .tp-sub {
        margin: calc(-1 * var(--boxel-sp-4xs)) 0 0;
        font-size: var(--trt-fs);
        color: var(--muted-foreground);
      }
      .tp-stats {
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        gap: calc(var(--trt-gap) * 0.66);
        margin: 0;
        padding: 0;
        list-style: none;
      }
      /* the mock's stat card: 7/10 padding, 12px 700 label with a dot,
         ~28px 400 value, ~10.5px subtle note */
      .tp-stat {
        display: grid;
        padding: var(--trt-py) var(--trt-px);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        color: var(--card-foreground);
      }
      /* mono caps label over the number, as the kit's .cap */
      .tp-stat-label {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-2xs);
        font: 600 0.5625rem / 1.3 var(--font-mono);
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--subtle-foreground);
      }
      .tp-dot {
        flex: none;
        inline-size: 0.4375rem;
        block-size: 0.4375rem;
        border-radius: 50%;
        background: var(--muted-foreground);
      }
      .tp-dot[data-tone='success'] {
        background: var(--success);
      }
      .tp-dot[data-tone='info'] {
        background: var(--info);
      }
      .tp-dot[data-tone='warning'] {
        background: var(--warning);
      }
      .tp-dot[data-tone='destructive'] {
        background: var(--destructive);
      }
      .tp-dot[data-tone='primary'] {
        background: var(--primary);
      }
      .tp-stat-value {
        margin-top: var(--boxel-sp-6xs);
        font-size: 1.375rem;
        font-weight: 700;
        line-height: 1.15;
        letter-spacing: -0.01em;
        font-variant-numeric: tabular-nums;
      }
      .tp-stat-note {
        font-size: calc(var(--trt-fs) - 0.09375rem);
        color: var(--subtle-foreground);
      }
      .tp-stat-note[data-tone='danger'] {
        color: var(--destructive-ink);
      }
      @container (width < 44rem) {
        .tp-stats {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
        h1 {
          font-size: 2rem;
        }
      }
      @container (width < 28rem) {
        h1 {
          font-size: 1.75rem;
        }
      }
    </style>
  </template>
}

interface Choice {
  value: string;
  label: string;
}

interface ListToolbarSignature {
  Args: {
    label: string;
    searchValue?: string;
    searchPlaceholder: string;
    onSearch: (value: string) => void;
    filterLabel?: string;
    filterOptions?: Choice[];
    filterValue?: string;
    onFilter?: (value: string) => void;
    viewOptions?: Choice[];
    view?: string;
    onView?: (value: string) => void;
  };
  /** primary actions at the end of the row, e.g. <bar.Action …/> */
  Blocks: { default: [TrackerBar] };
}

// A list tab's toolbar (the mock's Directory row): search, filter, view and
// the tab's actions in one LayoutControl. Search shrinks to an icon that
// opens the field; filter goes tabs → dropdown → ⋯; view goes into ⋯.
export class ListToolbar extends GlimmerComponent<ListToolbarSignature> {
  searchForms = SEARCH_FORMS;
  // The chips form needs the chips' real width, so the chooser steps down
  // to the dropdown instead of letting the chips wrap onto a second line.
  get filterForms() {
    let chips = (this.args.filterOptions ?? []).reduce(
      (rem, o) => rem + o.label.length * 0.5 + 1.75,
      0,
    );
    return F(['tabs', Math.max(chips, 8)], ['dropdown', 8], ['menu', 0]);
  }
  viewForms = VIEW_FORMS;

  get filterItems(): MenuEntry[] {
    return (this.args.filterOptions ?? []).map((o) => ({
      kind: 'radio' as const,
      group: 'filter',
      label: o.label,
      checked: this.args.filterValue === o.value,
      onSelect: () => this.args.onFilter?.(o.value),
    }));
  }
  get viewItems(): MenuEntry[] {
    return (this.args.viewOptions ?? []).map((o) => ({
      kind: 'radio' as const,
      group: 'view',
      label: o.label,
      checked: this.args.view === o.value,
      onSelect: () => this.args.onView?.(o.value),
    }));
  }
  get filterCurrent() {
    return this.args.filterOptions?.find(
      (o) => o.value === this.args.filterValue,
    )?.label;
  }

  <template>
    <div class='lt-band'><LayoutControl
        class='list-toolbar'
        @label={{@label}}
        @controlHeight={{CONTROL_HEIGHT}}
        as |lc|
      >
        <lc.Slot
          @id='search'
          @priority={{1}}
          @forms={{this.searchForms}}
          as |form|
        >
          {{! the field never leaves the row: typing is the main job of a list }}
          <SearchInput
            class='lt-search'
            data-form={{form}}
            @value={{@searchValue}}
            @placeholder={{if (eq form 'field-xs') 'Search' @searchPlaceholder}}
            @label={{@searchPlaceholder}}
            @onInput={{@onSearch}}
          />
        </lc.Slot>
        {{#if @filterOptions}}
          <lc.Slot
            @id='filter'
            @priority={{2}}
            @forms={{this.filterForms}}
            @label={{@filterLabel}}
            @menuItems={{this.filterItems}}
            as |form|
          >
            {{#if (eq form 'tabs')}}
              <FilterChips
                @options={{@filterOptions}}
                @value={{@filterValue}}
                @onValueChange={{@onFilter}}
                @label={{if @filterLabel @filterLabel 'Filter'}}
              />
            {{else}}
              <Menu
                @items={{this.filterItems}}
                @label={{if @filterLabel @filterLabel 'Filter'}}
              >
                <:trigger as |open toggle|>
                  <Button
                    type='button'
                    @size='xs'
                    @tone='neutral'
                    @appearance='outlined'
                    {{on 'click' toggle}}
                  >
                    {{this.filterCurrent}}
                  </Button>
                </:trigger>
              </Menu>
            {{/if}}
          </lc.Slot>
        {{/if}}
        <span class='lt-spacer'></span>
        {{#if @viewOptions}}
          <lc.Slot
            @id='view'
            @priority={{3}}
            @forms={{this.viewForms}}
            @label='View'
            @menuItems={{this.viewItems}}
          >
            <SegmentedControl
              @options={{@viewOptions}}
              @value={{@view}}
              @onValueChange={{@onView}}
              @label='View'
            />
          </lc.Slot>
        {{/if}}
        {{yield
          (hash Slot=lc.Slot Action=(component TrackerAction slot=lc.Slot))
        }}
      </LayoutControl></div>
    <style scoped>
      /* the mock's toolbar band: 40px between two hairlines */
      .lt-band {
        display: flex;
        align-items: center;
        min-height: 2.5rem;
        border-block: 1px solid var(--border);
      }
      .lt-band > * {
        flex: 1;
        min-width: 0;
      }
      .lt-search {
        inline-size: 15rem;
      }
      .lt-search[data-form='field-s'] {
        inline-size: 10.5rem;
      }
      .lt-search[data-form='field-xs'] {
        inline-size: 6rem;
      }
      .lt-spacer {
        flex-grow: 1;
      }
    </style>
  </template>
}
