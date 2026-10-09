import GlimmerComponent from '@glimmer/component';
import type Owner from '@ember/owner';
import { registerDestructor } from '@ember/destroyable';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { Alert } from '@cardstack/pretui/components/alert';
import { Button } from '@cardstack/pretui/components/button';
import { Input } from '@cardstack/pretui/components/input';
import type { CardDef } from '@cardstack/base/card-api';

import { Board, type BoardColumn } from '@cardstack/catalog/components/board';
import { slaClock } from '@cardstack/catalog/cards/service-desk/utils/sla-clock';
import { BreachRing } from './breach-ring';
import { LiveClock } from './live-clock';
import { ALERT_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { workflowKindColor } from '@cardstack/catalog/fields/workflow-state/workflow-state-field';
import {
  timerSnapshot,
  sortByUrgency,
} from '@cardstack/catalog/cards/service-desk/utils/sla';

export interface BoardCard {
  card: any;
  label?: string;
  /** The human line under the id. */
  title?: string;
  chipLabel?: string;
  chipHue?: string;
  ownerName?: string;
  /** Current workflow state key (read off the card by the caller). */
  stateKey?: string;
  timerFacts?: any;
}

interface Signature {
  Args: {
    /** The Workflow card — columns come from ITS states, in ITS order. */
    workflow: any;
    cards: BoardCard[];
    /**
     * The move, delegated to Run Workflow by the caller. Resolves on success;
     * REJECTS with the guard's message on refusal — the board shows the
     * reason and the card stays where the data says it is.
     */
    onMove: (card: any, toStateKey: string, note?: string) => Promise<void>;
    onOpen?: (card: any) => void;
  };
  Element: HTMLElement;
}

/**
 * Workflow Board — a kanban over ANY record set, grouped by the Workflow
 * card's own states.
 *
 * CONSUMES the catalog `Board`: drag engine, columns, keyboard selection all
 * come from there — this component only adds what a WORKFLOW needs: columns
 * derived from states, a guard prompt (requires-note asks inline before the
 * move commits), and a refusal message when Run Workflow rejects. It does
 * not draw a board of its own.
 */
export class WorkflowBoard extends GlimmerComponent<Signature> {
  constructor(owner: Owner, args: Signature['Args']) {
    super(owner, args);
    // The wall reads the shared clock, so its counts and order move as
    // deadlines pass rather than freezing at first render.
    slaClock.subscribe();
    registerDestructor(this, () => slaClock.unsubscribe());
  }

  @tracked pendingMove: { card: any; toKey: string } | null = null;
  @tracked pendingNote = '';
  @tracked refusal: string | null = null;

  get states() {
    return (this.args.workflow?.states ?? []).filter(Boolean);
  }

  get columns(): BoardColumn[] {
    return this.states.map((s: any) => {
      let cards = this.cardsIn(s.key).filter((c) => c.timerFacts);
      let nearest = cards.length
        ? timerSnapshot(
            sortByUrgency(cards, (c) => c.timerFacts, slaClock.now)[0]
              .timerFacts,
            slaClock.now,
          ).shortLabel
        : undefined;
      return {
        key: s.key,
        label: nearest
          ? `${s.label ?? s.key} · ${nearest}`
          : (s.label ?? s.key),
        color: workflowKindColor(s.kind).ring,
      };
    });
  }

  get items(): CardDef[] {
    return (this.args.cards ?? []).map((c) => c.card).filter(Boolean);
  }

  entryFor = (item: any): BoardCard | undefined =>
    (this.args.cards ?? []).find((c) => c.card?.id === item?.id);

  cardsIn = (stateKey: string) =>
    (this.args.cards ?? []).filter((c) => c.stateKey === stateKey);

  columnKeyFor = (item: CardDef) =>
    this.entryFor(item)?.stateKey ?? this.states[0]?.key;

  handleMove = async (item: CardDef, toKey: string) => {
    this.refusal = null;
    let entry = this.entryFor(item);
    let transition = (this.args.workflow?.transitions ?? []).find(
      (t: any) => t.from === entry?.stateKey && t.to === toKey,
    );
    if (transition?.guard === 'requires-note') {
      // The card goes back until the note is confirmed, which commits the move.
      this.pendingMove = { card: item, toKey };
      this.pendingNote = '';
      return false;
    }
    return this.commit(item, toKey, undefined);
  };

  commit = async (card: any, toKey: string, note?: string) => {
    try {
      await this.args.onMove(card, toKey, note);
      this.pendingMove = null;
      this.pendingNote = '';
    } catch (e: any) {
      // The refusal names the rule; the data did not change, so the board
      // re-renders the card where it was — the snap-back is the truth.
      this.refusal = e?.message ?? String(e);
      this.pendingMove = null;
      return false;
    }
    return undefined;
  };

  setNote = (v: string) => (this.pendingNote = v);
  get noteMissing() {
    return !this.pendingNote.trim();
  }
  confirmGuard = async () => {
    if (!this.pendingMove) return;
    await this.commit(
      this.pendingMove.card,
      this.pendingMove.toKey,
      this.pendingNote,
    );
  };
  cancelGuard = () => {
    this.pendingMove = null;
    this.pendingNote = '';
  };

  open = (item: CardDef) => this.args.onOpen?.(item);

  <template>
    <div class='wfb' ...attributes>
      {{#if this.refusal}}
        <Alert
          @tone='danger'
          @title='That move was refused'
          style={{ALERT_STYLE.danger}}
        >{{this.refusal}}</Alert>
      {{/if}}
      {{#if this.pendingMove}}
        <div class='wfb-guard' role='dialog' aria-label='Transition guard'>
          <p class='wfb-guard-label'>Moving to “{{this.pendingMove.toKey}}”
            needs a note — why is this record ready?</p>
          <Input
            @value={{this.pendingNote}}
            @onInput={{this.setNote}}
            aria-label='Note for this move'
          />
          <div class='wfb-guard-actions'>
            <Button
              @size='s'
              @tone='primary'
              @appearance='accent'
              @disabled={{this.noteMissing}}
              {{on 'click' this.confirmGuard}}
            >Move with note</Button>
            <Button
              @size='s'
              @tone='neutral'
              @appearance='outlined'
              {{on 'click' this.cancelGuard}}
            >Cancel — card stays</Button>
          </div>
        </div>
      {{/if}}
      <Board
        @boardLabel={{@workflow.title}}
        @cardSize='regular-tile'
        @items={{this.items}}
        @columns={{this.columns}}
        @columnKeyFor={{this.columnKeyFor}}
        @onMove={{this.handleMove}}
        @onOpen={{this.open}}
      >
        <:card as |item|>
          {{#let (this.entryFor item) as |entry|}}
            <div class='wfb-card'>
              <span class='wfb-line'>
                {{#if entry.timerFacts}}<BreachRing
                    @facts={{entry.timerFacts}}
                    @size={{22}}
                  />{{/if}}
                {{#if entry.label}}<span
                    class='wfb-title'
                  >{{entry.label}}</span>{{/if}}
                {{#if entry.chipLabel}}<StatePill
                    @label={{entry.chipLabel}}
                    @hue={{entry.chipHue}}
                  />{{/if}}
              </span>
              <span class='wfb-subject'>{{if
                  entry.title
                  entry.title
                  item.cardTitle
                }}</span>
              <span class='wfb-meta'>
                <span class='{{unless entry.ownerName "wfb-unowned"}}'>{{if
                    entry.ownerName
                    entry.ownerName
                    'unassigned'
                  }}</span>
                {{#if entry.timerFacts}}<LiveClock
                    @facts={{entry.timerFacts}}
                    class='wfb-clock'
                  />{{/if}}
              </span>
            </div>
          {{/let}}
        </:card>
      </Board>
    </div>
    <style scoped>
      .wfb {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        min-height: 18rem;
      }
      .wfb-guard {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-4xs);
        padding: var(--boxel-sp-sm);
        border: 1.5px dashed var(--primary);
        border-radius: var(--boxel-border-radius);
        background: color-mix(in oklab, var(--primary) 6%, var(--card));
        max-width: 40rem;
      }
      .wfb-guard-label {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
      }
      .wfb-guard-actions {
        display: flex;
        gap: var(--boxel-sp-4xs);
      }
      .wfb-card {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-4xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        min-width: 0;
        height: 100%;
      }
      .wfb-line {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-4xs);
        min-width: 0;
      }
      .wfb-title {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .wfb-subject {
        font-size: var(--boxel-font-size);
        font-weight: 500;
        line-height: 1.35;
        flex: 1;
        overflow: hidden;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
      }
      .wfb-meta {
        display: flex;
        justify-content: space-between;
        gap: var(--boxel-sp-4xs);
        margin-top: auto;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      .wfb-unowned {
        color: var(--warning-ink);
        font-style: italic;
      }
      .wfb-clock {
        font-size: var(--boxel-font-size-sm);
      }
    </style>
  </template>
}

export default WorkflowBoard;
