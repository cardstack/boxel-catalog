import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { debounce } from 'lodash';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Button } from '../../../ui-component/components/button';
import { SegmentedControl } from '../../../ui-component/components/segmented-control';
import { Board, type BoardColumn } from '../../../components/board';
import { StatePill } from '../../../components/state-pill';
import { FilterChips } from '../../../ui-component/components/filter-chips';
import { Panel } from '../../../ui-component/components/panel';
import { SearchInput } from '../../../ui-component/components/search-input';
import {
  type Escalation,
  escalationStatusHue,
} from '../../service-desk/escalation';
import { CrossRecordTimeline } from '../../service-desk/components/cross-record-timeline';

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
  };
}

/** The desk's Escalations tab: the ladder by receiving level, the awaiting-ack
    list and the history. */
export class DeskEscalations extends GlimmerComponent<Signature> {
  @tracked escView: 'lanes' | 'list' = 'lanes';
  @tracked escSearch = '';
  @tracked escStatus = 'all';

  shield = (e: Event) => e.stopPropagation();
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
      <div class='esc-toolbar'>
        <SearchInput
          class='esc-search'
          @value={{this.escSearch}}
          @placeholder='Search subject, reason, level or who raised it'
          @label='Search escalations'
          @size='s'
          @onInput={{this.setEscSearch}}
        />
        <FilterChips
          @options={{this.escOptions}}
          @value={{this.escStatus}}
          @onValueChange={{this.setEscStatus}}
          @label='Filter by status'
          @size='s'
          @appearance='solid'
        />
        <SegmentedControl
          class='esc-view'
          @label='Escalation view'
          @options={{ESCALATION_VIEWS}}
          @value={{this.escView}}
          @onValueChange={{this.setEscView}}
          @size='s'
          @appearance='tinted'
        />
      </div>
      {{#if (eq this.escView 'lanes')}}
        {{#if @refusal}}<p
            class='desk-refusal'
            role='alert'
          >{{@refusal}}</p>{{/if}}
        <Board
          @boardLabel='Escalation ladder'
          @cardSize='large-tile'
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
                  <StatePill
                    @label={{e.status}}
                    @hue={{escalationStatusHue e.status}}
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
                    @tone='primary'
                    @appearance='accent'
                    @size='xs'
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
                @tone='primary'
                @appearance='accent'
                @size='xs'
                {{on 'click' (fn @onAcknowledge e)}}
              >Acknowledge</Button>
            {{/if}}
          </div>
        {{else}}
          {{#if @isLoading}}
            <p class='desk-loading' role='status'>Loading escalations…</p>
          {{else}}
            <p class='desk-empty'>✓ Every escalation acknowledged.</p>
          {{/if}}
        {{/each}}
      {{/if}}
      <Panel @title='History'>
        <CrossRecordTimeline
          @events={{this.escalationEvents}}
          @emptyLabel='No escalations yet — a quiet ladder is a good ladder.'
        />
      </Panel>
    </div>
    <style scoped>
      .esc-tab {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
      }
      .esc-toolbar {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
      }
      .esc-search {
        flex: 1;
        min-width: 12rem;
        max-width: 24rem;
      }
      .esc-view {
        --pretui-seg-radius: var(--boxel-border-radius-pill);
        margin-left: auto;
      }
      .ecard {
        display: flex;
        flex-direction: column;
        align-items: flex-start;
        gap: var(--boxel-sp-4xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        min-width: 0;
        height: 100%;
      }
      .ecard-top {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-4xs);
        align-self: stretch;
      }
      .ecard-id,
      .ecard-foot {
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      .ecard-title {
        font-size: var(--boxel-font-size);
        font-weight: 600;
        line-height: 1.35;
      }
      .ecard-overdue {
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
        color: var(--destructive-ink);
      }
      .ecard-action {
        margin-top: var(--boxel-sp-4xs);
      }
      .esc-line {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }

      .desk-loading,
      .desk-empty {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      .desk-refusal {
        margin: 0;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-left: 0.1875rem solid var(--destructive);
        border-radius: 0 var(--radius) var(--radius) 0;
        background: color-mix(in oklab, var(--destructive) 8%, var(--card));
        font-size: var(--boxel-font-size-sm);
      }
    </style>
  </template>
}
