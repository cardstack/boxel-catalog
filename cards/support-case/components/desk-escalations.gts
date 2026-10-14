import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { debounce } from 'lodash';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Button } from '@cardstack/pretui/components/button';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import { Board, type BoardColumn } from '../../../components/board';
import { CollectionToolbar } from '../../../components/collection-toolbar';
import {
  type Escalation,
  escalationStatusHue,
} from '../../service-desk/escalation';
import { CrossRecordTimeline } from '../../service-desk/components/cross-record-timeline';
import { DeskLaneCard } from './desk-lane-card';

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
  get escBadges() {
    let st = ['open', 'acknowledged', 'resolved', 'cancelled'];
    return [
      { id: 'all', label: 'All', count: this.args.escalations.length },
      ...st.map((x) => ({
        id: x,
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
      <CollectionToolbar
        @search={{this.escSearch}}
        @onSearch={{this.setEscSearch}}
        @placeholder='Search subject, reason, level or who raised it'
        @badges={{this.escBadges}}
        @activeBadge={{this.escStatus}}
        @onBadge={{this.setEscStatus}}
      >
        <:right>
          <SegmentedControl
            @label='Escalation view'
            @options={{ESCALATION_VIEWS}}
            @value={{this.escView}}
            @onChange={{this.setEscView}}
          />
        </:right>
      </CollectionToolbar>
      {{#if (eq this.escView 'lanes')}}
        {{#if @refusal}}<p
            class='desk-refusal'
            role='alert'
          >{{@refusal}}</p>{{/if}}
        <Board
          @boardLabel='Escalation ladder'
          @cardSize='regular-tile'
          @items={{this.escalationItems}}
          @columns={{this.escalationColumns}}
          @columnKeyFor={{this.escalationKeyFor}}
          @onMove={{this.moveEscalation}}
          @onOpen={{@onOpen}}
        >
          <:card as |card|>
            {{#let (this.asEscalation card) as |e|}}
              <DeskLaneCard
                @label='{{e.fromLevel.key}} → {{e.toLevel.key}}'
                @pillLabel={{e.status}}
                @hue={{escalationStatusHue e.status}}
              >
                <:default>{{this.subjectTitle e}}</:default>
                <:foot><span>{{e.reason}}
                    ·
                    {{this.ackDue e}}
                    · by
                    {{e.raisedByName}}</span>{{#if (eq e.ackOverdue 'yes')}}<b
                      class='lcard-overdue'
                    >ack overdue</b>{{/if}}</:foot>
                <:action>
                  {{#if (eq e.status 'open')}}
                    {{! The board takes pointer capture on pointerdown, so the button stops it there to keep its own click. }}
                    {{! template-lint-disable no-pointer-down-event-binding }}
                    <Button
                      @tone='primary'
                      @appearance='filled'
                      @size='xs'
                      {{on 'pointerdown' this.shield}}
                      {{on 'click' (fn @onAcknowledge e)}}
                    >Acknowledge</Button>
                    {{! template-lint-enable no-pointer-down-event-binding }}
                  {{/if}}
                </:action>
              </DeskLaneCard>
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
            <Button
              @tone='primary'
              @appearance='filled'
              @size='xs'
              {{on 'click' (fn @onAcknowledge e)}}
            >Acknowledge</Button>
          </div>
        {{else}}
          {{#if @isLoading}}
            <p class='desk-loading' role='status'>Loading escalations…</p>
          {{else}}
            <p class='desk-empty'>✓ Every escalation acknowledged.</p>
          {{/if}}
        {{/each}}
      {{/if}}
      <section class='esc-history'>
        <h3 class='esc-history-title'>History</h3>
        <CrossRecordTimeline
          @events={{this.escalationEvents}}
          @emptyLabel='No escalations yet — a quiet ladder is a good ladder.'
        />
      </section>
    </div>
    <style scoped>
      .lcard-overdue {
        color: var(--destructive-ink);
      }
      .esc-tab {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
      }
      .esc-history {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
      }
      .esc-line {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .esc-history-title {
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        letter-spacing: 0.1em;
        text-transform: uppercase;
        color: var(--muted-foreground);
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
