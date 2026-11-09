import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { debounce } from 'lodash';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Button } from '@cardstack/pretui/components/button';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import { Board, type BoardColumn } from '@cardstack/catalog/components/board';
import { StatusChip } from '@cardstack/pretui/components/status-chip';
import { LayoutControl } from '@cardstack/pretui/components/layout-control';
import PlusIcon from '@cardstack/boxel-icons/plus';
import { FilterChips } from '@cardstack/pretui/components/filter-chips';
import { SearchInput } from '@cardstack/pretui/components/search-input';
import {
  type Escalation,
  escalationStatusHue,
} from '../../service-desk/escalation';
import { CrossRecordTimeline } from '../../service-desk/components/cross-record-timeline';

import { F, SEARCH_FORMS, VIEW_FORMS, shield } from './desk-forms';

const CHIP_FORMS = F(['chips', 28], ['menu', 0]);
const ADD_FORMS = F(['label', 9], ['icon', 2]);

const ESCALATION_VIEWS = [
  { value: 'lanes', label: 'The ladder' },
  { value: 'list', label: 'Awaiting ack' },
];

interface Signature {
  Args: {
    escalations: Escalation[];
    /** True while the escalations query has not returned yet. */
    isLoading: boolean;
    /** Why the last drag was refused, if it was. */
    refusal: string | null;
    onOpen: (card: any) => void;
    onAcknowledge: (e: Escalation) => void;
    onEscalate: (e: Escalation, toLevelKey: string) => unknown;
    titleOf: (card: any) => string;
    /** The tab's primary action, pinned at the end of the toolbar. */
    onRaise: () => void;
  };
}

/** The desk's Escalations tab: the ladder by receiving level, the awaiting-ack
    list and the history. */
export class DeskEscalations extends GlimmerComponent<Signature> {
  @tracked escView: 'lanes' | 'list' = 'lanes';
  @tracked escSearch = '';
  @tracked escStatus = 'all';

  shield = shield;
  subjectTitle = (e: Escalation) => e.subjectTitle ?? '?';
  // The Board yields plain cards; every card on this board is an Escalation.
  asEscalation = (card: unknown) => card as Escalation;
  moveEscalation = (card: unknown, toLevelKey: string) =>
    this.args.onEscalate(card as Escalation, toLevelKey);

  /** Escalations as a kanban by receiving level — the ladder, drawn with the shared Board. */
  escalationColumns: BoardColumn[] = [
    {
      key: 'L1',
      label: 'L1',
      color: 'var(--muted-foreground)',
    },
    {
      key: 'L2',
      label: 'L2',
      color: 'var(--primary)',
    },
    { key: 'L3', label: 'L3', color: 'var(--warning)' },
    { key: 'exec', label: 'Exec', color: 'var(--destructive)' },
  ];
  escalationKeyFor = (e: any) => (e?.toLevel?.key as string) ?? 'L1';
  private debouncedSetEscSearch = debounce(
    (v: string) => (this.escSearch = v),
    250,
  );
  setEscSearch = (v: string) => this.debouncedSetEscSearch(v);
  setEscStatus = (id: string) => (this.escStatus = id);
  get escOptions() {
    let st = ['open', 'acknowledged', 'resolved', 'cancelled'];
    return [
      { value: 'all', label: 'All', count: this.args.escalations.length },
      ...st.map((x) => ({
        value: x,
        label: x[0]!.toUpperCase() + x.slice(1),
        count: this.args.escalations.filter((e) => e.status === x).length,
      })),
    ];
  }
  get escalationItems() {
    let q = this.escSearch.trim().toLowerCase();
    return this.args.escalations.filter((e) => {
      let statusOk =
        this.escStatus === 'all'
          ? e.status !== 'cancelled'
          : e.status === this.escStatus;
      let textOk =
        !q ||
        this.subjectTitle(e).toLowerCase().includes(q) ||
        (e.reason ?? '').toLowerCase().includes(q) ||
        (e.raisedByName ?? '').toLowerCase().includes(q) ||
        (e.toLevel?.key ?? '').toLowerCase().includes(q);
      return statusOk && Boolean(textOk);
    });
  }
  setEscView = (v: string) => (this.escView = v as 'lanes' | 'list');
  ackDue = (e: Escalation) =>
    e.toLevel?.ackTargetMinutes
      ? `${e.toLevel.ackTargetMinutes}m ack target`
      : 'no ack target';

  // escalation timeline events for the escalations tab
  get escalationEvents() {
    return this.args.escalations.map((e) => ({
      at: e.raisedAt,
      label: `${e.title} · ${e.reason} on ${this.subjectTitle(e)}`,
      by: e.raisedByName,
      intent:
        e.status === 'open'
          ? ('amber' as const)
          : e.status === 'cancelled'
            ? ('slate' as const)
            : ('green' as const),
    }));
  }

  <template>
    <div class='esc-tab'>
      <LayoutControl
        @label='Escalation tools'
        @controlHeight='1.625rem'
        as |lc|
      >
        <lc.Slot
          @id='search'
          @priority={{2}}
          @forms={{SEARCH_FORMS}}
          @label='Search'
        >
          <div class='desk-search'><SearchInput
              @value={{this.escSearch}}
              @placeholder='Search subject, reason, level or who raised it'
              @onInput={{this.setEscSearch}}
            /></div>
        </lc.Slot>
        <lc.Slot
          @id='status'
          @priority={{3}}
          @forms={{CHIP_FORMS}}
          @label='Status'
        >
          <FilterChips
            @options={{this.escOptions}}
            @value={{this.escStatus}}
            @onValueChange={{this.setEscStatus}}
            @label='Filter by status'
          />
        </lc.Slot>
        <lc.Slot @id='view' @priority={{1}} @forms={{VIEW_FORMS}} @label='View'>
          <SegmentedControl
            @label='Escalation view'
            @options={{ESCALATION_VIEWS}}
            @value={{this.escView}}
            @onValueChange={{this.setEscView}}
          />
        </lc.Slot>
        <lc.Slot
          @id='raise'
          @priority={{0}}
          @pinned={{true}}
          @forms={{ADD_FORMS}}
          @label='Raise escalation'
          as |form|
        >
          <Button
            class='esc-add'
            @icon={{PlusIcon}}
            @tone='primary'
            @appearance='accent'
            @size='s'
            @display={{if (eq form 'icon') 'icon' 'label'}}
            @label='Raise escalation'
            {{on 'click' @onRaise}}
          >Raise escalation</Button>
        </lc.Slot>
      </LayoutControl>
      {{#if (eq this.escView 'lanes')}}
        {{#if @refusal}}<p
            class='desk-refusal'
            role='alert'
          >{{@refusal}}</p>{{/if}}
        <Board
          @boardLabel='Escalation ladder'
          @cardSize='triple-strip'
          @items={{this.escalationItems}}
          @columns={{this.escalationColumns}}
          @columnKeyFor={{this.escalationKeyFor}}
          @onMove={{this.moveEscalation}}
          @onOpen={{@onOpen}}
        >
          <:card as |card|>
            {{#let (this.asEscalation card) as |e|}}
              <div class='ecard'>
                <span class='ecard-top'>
                  <span class='ecard-id'>{{e.fromLevel.key}}
                    →
                    {{e.toLevel.key}}</span>
                  <StatusChip
                    @value={{e.status}}
                    @hue={{escalationStatusHue e.status}}
                    @appearance='plain'
                  />
                </span>
                <span class='ecard-title'>{{this.subjectTitle e}}</span>
                <span class='ecard-foot'>{{e.reason}}
                  ·
                  {{this.ackDue e}}
                  · by
                  {{e.raisedByName}}</span>
                {{#if (eq e.ackOverdue 'yes')}}<b class='ecard-overdue'>ack
                    overdue</b>{{/if}}
                {{#if (eq e.status 'open')}}
                  {{! The board takes pointer capture on pointerdown, so the button stops it there to keep its own click. }}
                  {{! template-lint-disable no-pointer-down-event-binding }}
                  <Button
                    class='ecard-action'
                    @tone='neutral'
                    @appearance='plain'
                    @size='s'
                    {{on 'pointerdown' this.shield}}
                    {{on 'click' (fn @onAcknowledge e)}}
                  >Acknowledge</Button>
                  {{! template-lint-enable no-pointer-down-event-binding }}
                {{/if}}
              </div>
            {{/let}}
          </:card>
        </Board>
      {{else}}
        {{#each this.escalationItems as |e|}}
          <div class='esc-line'>
            <Button @appearance='plain' @size='s' {{on 'click' (fn @onOpen e)}}>
              {{@titleOf e}}
              ·
              {{e.reason}}
              · on
              {{this.subjectTitle e}}
            </Button>
            {{#if (eq e.status 'open')}}
              <Button
                @tone='neutral'
                @appearance='plain'
                @size='s'
                {{on 'click' (fn @onAcknowledge e)}}
              >Acknowledge</Button>
            {{/if}}
          </div>
        {{else}}
          {{#if @isLoading}}
            <p class='desk-loading' role='status'>Loading escalations…</p>
          {{else}}
            <p class='desk-empty'>Every escalation acknowledged.</p>
          {{/if}}
        {{/each}}
      {{/if}}
      <section class='esc-history' aria-labelledby='esc-history-h'>
        <div class='esc-head'>
          <h2 id='esc-history-h'>History</h2>
          <p>every escalation raised</p>
        </div>
        <CrossRecordTimeline
          class='esc-history-body'
          @events={{this.escalationEvents}}
          @emptyLabel='No escalations yet — a quiet ladder is a good ladder.'
        />
      </section>
    </div>
    <style scoped>
      .esc-tab {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
      }
      .desk-search {
        inline-size: 15rem;
      }
      .esc-add {
        margin-inline-start: auto;
      }
      .ecard {
        display: flex;
        flex-direction: column;
        align-items: flex-start;
        gap: var(--boxel-sp-4xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        min-inline-size: 0;
        block-size: 100%;
      }
      .ecard-top {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-4xs);
        align-self: stretch;
      }
      .ecard-id {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .ecard-foot {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .ecard-title {
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .ecard-overdue {
        font-size: var(--boxel-font-size-2xs);
        font-weight: 600;
        color: var(--destructive);
      }
      .ecard-action {
        align-self: flex-end;
      }
      .esc-line {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .esc-history {
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        color: var(--card-foreground);
        overflow: hidden;
      }
      .esc-head {
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-block-end: 1px solid var(--border);
      }
      .esc-head h2 {
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .esc-head p {
        margin: 0;
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .esc-history-body {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
      }
      .desk-loading,
      .desk-empty {
        margin: 0;
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .desk-refusal {
        margin: 0;
        padding: var(--boxel-sp-4xs) var(--boxel-sp-sm);
        border: 1px solid var(--border);
        border-inline-start: 0.1875rem solid var(--destructive);
        border-radius: var(--radius);
        background: var(--card);
        font-size: var(--boxel-font-size-2xs);
      }
    </style>
  </template>
}
