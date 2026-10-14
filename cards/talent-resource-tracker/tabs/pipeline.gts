import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq, or } from '@cardstack/boxel-ui/helpers';
import type {
  KanbanColumnConfig,
  KanbanPlacement,
} from '@cardstack/boxel-ui/components';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import {
  Candidate,
  CANDIDATE_STAGES,
  CANDIDATE_STAGE_COLORS,
} from '../../hr/candidate';
import { Button } from '@cardstack/pretui/components/button';
import { Board } from '@cardstack/pretui/components/board';
import { offerStatusLabel } from '../../hr/offer';
import { ApproveOfferCommand } from '../../hr/commands/approve-offer-command';
import { ExtendOfferCommand } from '../../hr/commands/extend-offer-command';
import { AdvanceToOfferCommand } from '../../hr/commands/advance-to-offer-command';
import { daysBetween, toLocalDate } from '../dates';
import { stateColorOf } from '../../../components/state-pill';
import { getComponent } from '../shared';
import type { TrackerView } from '../talent-resource-tracker';

interface Signature {
  Args: {
    tracker: TrackerView;
  };
}

export class PipelineTab extends GlimmerComponent<Signature> {
  // Whose turn is it — a candidate's own status tells you WHERE they are;
  // this tells you WHO needs to act next. Dashboard's "needs us" count and
  // Pipeline's card badges both read from this single source of truth.
  // Same denormalized-id matching rationale as whoseTurn below.
  hasUpcomingInterview = (candidate: Candidate | undefined): boolean => {
    if (!candidate?.id) {
      return false;
    }
    return this.args.tracker.meetings.some(
      (m) =>
        m.candidateId === candidate.id &&
        m.date &&
        toLocalDate(m.date).getTime() > Date.now(),
    );
  };

  get kanbanColumns(): KanbanColumnConfig[] {
    return CANDIDATE_STAGES.map((stage, index) => ({
      key: stage,
      label: stage,
      color: stateColorOf(CANDIDATE_STAGE_COLORS, stage).ring,
      collapsed: false,
      wipLimit: null,
      sortOrder: index,
    }));
  }

  // The board is a controlled component: it renders exactly what these
  // placements say and hands back new ones on drop. sortOrder is 1-based
  // within a column, so it is grouped per column here rather than reusing the
  // flat candidates index. Candidates with no boardOrder yet sort last, in
  // their existing link order.
  get kanbanPlacements(): KanbanPlacement[] {
    let byColumn = new Map<string, { index: number; order: number }[]>();
    this.args.tracker.candidates.forEach((candidate, index) => {
      let columnId = candidate.status ?? CANDIDATE_STAGES[0];
      let column = byColumn.get(columnId);
      if (!column) {
        column = [];
        byColumn.set(columnId, column);
      }
      column.push({ index, order: candidate.boardOrder ?? Infinity });
    });
    let placements: KanbanPlacement[] = [];
    for (let [columnId, entries] of byColumn) {
      entries
        .sort((a, b) => a.order - b.order || a.index - b.index)
        .forEach((entry, position) => {
          placements.push({
            columnId,
            index: entry.index,
            sortOrder: position + 1,
          });
        });
    }
    return placements;
  }

  candidateAt = (index: number): Candidate | undefined => {
    return this.args.tracker.candidates[index];
  };

  statusAt = (index: number): string | undefined => {
    return this.args.tracker.candidates[index]?.status;
  };

  openCandidateAt = (index: number) => {
    let candidate = this.args.tracker.candidates[index];
    if (candidate) {
      this.args.tracker.openCard(candidate);
    }
  };

  handleKanbanChange = (newPlacements: KanbanPlacement[]) => {
    let reordered: Candidate[] = [];
    for (let placement of newPlacements) {
      let candidate = this.args.tracker.candidates[placement.index];
      if (!candidate) {
        continue;
      }
      let targetStage = placement.columnId;

      // Same column: a pure re-sort, so only the position needs persisting.
      if (candidate.status === targetStage) {
        if (candidate.boardOrder !== placement.sortOrder) {
          candidate.boardOrder = placement.sortOrder;
          reordered.push(candidate);
        }
        continue;
      }
      // Hired is terminal — leave the card where it is and let the board
      // re-render it back into its column.
      if (candidate.status === 'hired') {
        continue;
      }
      if (targetStage === 'hired' && candidate.status !== 'offer') {
        this.args.tracker.actionError = `Only candidates at the "offer" stage can be approved.`;
        continue;
      }
      // The stage commands below save the candidate, which carries the new
      // position along with the new status.
      candidate.boardOrder = placement.sortOrder;
      if (targetStage === 'hired') {
        this.approveOrReviewChain(candidate);
        continue;
      }
      if (targetStage === 'rejected') {
        void this.reject(candidate);
        continue;
      }
      // Dropping into `offer` runs the same command the button does, so the
      // draft Offer gets created either way — the three meaningful drops are
      // symmetric now instead of two running commands and one not.
      if (targetStage === 'offer' && candidate.status === 'interviewing') {
        void this.advanceToOffer(candidate);
        continue;
      }
      // Dragging backwards past a live offer must reconcile the offer too,
      // or the board manufactures contradictions (a card at "interviewing"
      // whose offer still reads extended/accepted).
      if (
        candidate.offerState &&
        (targetStage === 'applied' ||
          targetStage === 'screening' ||
          targetStage === 'interviewing')
      ) {
        if (candidate.offerState === 'accepted') {
          this.args.tracker.actionError = `${
            candidate.name ?? 'This candidate'
          } already accepted the offer — drag to Hired, or rescind it on the Offer card first.`;
          continue;
        }
        void this.moveBackPastOffer(candidate, targetStage);
        continue;
      }
      void this.moveCandidateStage(candidate, targetStage);
    }
    if (reordered.length) {
      void this.saveCandidates(reordered);
    }
  };

  private async saveCandidates(candidates: Candidate[]) {
    let commandContext = this.args.tracker.args.context?.commandContext;
    if (!commandContext) {
      this.args.tracker.actionError = 'Commands are unavailable in this mode';
      return;
    }
    let saveCard = new SaveCardCommand(commandContext);
    for (let candidate of candidates) {
      await saveCard.execute({ card: candidate } as any);
    }
  }

  private async moveCandidateStage(candidate: Candidate, status: string) {
    candidate.status = status as Candidate['status'];
    await this.saveCandidates([candidate]);
  }

  // A backward drag past a live offer withdraws it on the record: a draft
  // or extended offer becomes `rescinded` (the vocabulary's word for "we
  // pulled it back"), a declined/rescinded one just stops mirroring onto
  // the candidate — either way the pipeline card resets cleanly and the
  // Offer card keeps the honest history. Accepted offers never reach here
  // (blocked in handleKanbanChange).
  private async moveBackPastOffer(candidate: Candidate, targetStage: string) {
    let commandContext = this.args.tracker.args.context?.commandContext;
    if (!commandContext) {
      this.args.tracker.actionError = 'Commands are unavailable in this mode';
      return;
    }
    // Resolve via the live offers query by denormalized id — never the
    // `candidate.offer` linksTo (render/click race, see openCandidateOffer).
    let offer = this.args.tracker.offers.find(
      (o) => o?.candidateId && o.candidateId === candidate.id,
    );
    if (offer && (offer.status === 'draft' || offer.status === 'extended')) {
      offer.status = 'rescinded';
      await new SaveCardCommand(commandContext).execute({
        card: offer,
      } as any);
    }
    candidate.offerState = '';
    candidate.status = targetStage as Candidate['status'];
    await this.saveCandidates([candidate]);
  }

  isScheduling = (candidate: Candidate | undefined): boolean => {
    return (
      Boolean(candidate?.id) &&
      this.args.tracker.scheduleDialogCandidate?.id === candidate?.id
    );
  };

  // Opens the availability-aware slot-picker dialog. The dialog computes free hourly slots from the
  // live meetingsQuery; ScheduleInterviewCommand re-checks for double
  // bookings server-side and throws on a clash, which lands in
  // scheduleError → the dialog's role='alert' line.
  scheduleInterview = (candidate: Candidate) => {
    this.args.tracker.scheduleError = undefined;
    this.args.tracker.scheduleDialogCandidate = candidate;
  };

  approve = async (candidate: Candidate) => {
    await this.args.tracker.runCommand(candidate, async (commandContext) => {
      await new ApproveOfferCommand(commandContext).execute({
        candidate,
      } as any);
    });
  };

  // The offer's approvalChain link is dereferenced here, inside the click
  // handler's body — not during render via `fn`'s eager arg evaluation —
  // for the same async-link-load reason openCandidateOffer's own comment
  // explains. When a chain is configured and not yet fully approved, hiring
  // is blocked (ApproveOfferCommand enforces this server-side too); the
  // click instead surfaces a message and opens the Offer so the chain can be
  // reviewed/decided there.
  approveOrReviewChain = (candidate: Candidate) => {
    let chain = candidate.offer?.approvalChain;
    if (chain?.steps?.length && chain.status !== 'approved') {
      this.args.tracker.actionError =
        'Approval chain in progress — open the Offer to review.';
      this.openCandidateOffer(candidate);
      return;
    }
    void this.approve(candidate);
  };

  // Opens the structured reject dialog. The reason drives the Offers
  // dashboard breakdown, so it comes from a fixed set of values.
  reject = (candidate: Candidate) => {
    this.args.tracker.rejectDialogCandidate = candidate;
  };

  extendOffer = async (candidate: Candidate) => {
    // The new Offer reaches the Offers tab via the live `offersQuery` —
    // nothing to link back onto the tracker.
    await this.args.tracker.runCommand(
      candidate,
      async (commandContext) => {
        return (await new ExtendOfferCommand(commandContext).execute({
          candidate,
        } as any)) as any;
      },
      'send',
    );
  };

  advanceToOffer = async (candidate: Candidate) => {
    await this.args.tracker.runCommand(
      candidate,
      async (commandContext) => {
        await new AdvanceToOfferCommand(commandContext).execute({
          candidate,
        } as any);
      },
      'create',
    );
  };

  // Label for the offer link. Reads the scalar mirror rather than the
  // linked card's status, for the same hot-path reason as whoseTurn.
  // `fn` evaluates its positional args eagerly, at the point the helper
  // itself runs during render — not lazily when the bound function is later
  // called. `(fn this.args.tracker.openCard candidateModel.offer)` therefore dereferences
  // the `offer` linksTo on every render of every interviewing candidate,
  // racing the same async link-load assertion this guard was meant to avoid.
  // Wrapping the access inside this action defers it to actual click time.
  openCandidateOffer = (candidate: Candidate) => {
    // Never dereference `candidate.offer` here — with live-query instances
    // the linksTo is not eagerly loaded, so a synchronous read races the
    // async link load and the click opens nothing. Match the Offer from the
    // live offers query by its denormalized own-attribute id instead.
    let offer = this.args.tracker.offers.find(
      (o) => o?.candidateId && o.candidateId === candidate.id,
    );
    this.args.tracker.openCard(offer);
  };

  offerLabel = (candidate: Candidate | undefined): string => {
    return offerStatusLabel(candidate?.offerState) ?? 'not sent';
  };

  isBusyCandidate = (candidate: Candidate | undefined): boolean => {
    return (
      Boolean(candidate?.id) &&
      this.args.tracker.busyCandidateId === candidate?.id
    );
  };

  stopEvent = (event: Event) => {
    event.stopPropagation();
  };

  // Time-in-stage aging: recruiters triage by how long a candidate has been
  // sitting in the pipeline. Only open stages age.
  pipelineAge = (
    candidate: Candidate | undefined,
  ): { label: string; stale: boolean } | undefined => {
    if (!candidate?.appliedDate) return undefined;
    let status = candidate.status;
    if (status === 'hired' || status === 'rejected') return undefined;
    let days = daysBetween(toLocalDate(candidate.appliedDate), new Date());
    if (days === undefined || days < 0) return undefined;
    return { label: `Day ${days + 1}`, stale: days >= 30 };
  };

  // Interview scorecard rollup: average of linked Meetings' interviewScore.
  // Whether the extras strip under a kanban card would render anything at all.
  // The `.card-extras:empty` CSS fallback cannot do this job: the template's
  // newlines and indentation are whitespace text nodes, so the div is never
  // truly :empty and its padding still reserves a dead strip under the card.
  // Guarding in the template removes the element outright.
  hasCardExtras = (candidate: Candidate | undefined): boolean => {
    let status = candidate?.status;
    if (!status) {
      return false;
    }
    // Non-terminal stages always render at least the whose-turn chip, and
    // every stage-action button sits under a non-terminal branch.
    if (status !== 'hired' && status !== 'rejected') {
      return true;
    }
    // Terminal stages: pipelineAge returns undefined by design, so the score
    // rollup is the only thing that can still appear.
    return Boolean(this.avgInterviewScore(candidate));
  };

  avgInterviewScore = (
    candidate: Candidate | undefined,
  ): { label: string } | undefined => {
    if (!candidate?.id) return undefined;
    let scores = this.args.tracker.meetings
      .filter((m) => m.candidateId === candidate.id)
      .map((m) => m.interviewScore)
      .filter((v): v is number => typeof v === 'number' && Number.isFinite(v));
    if (!scores.length) return undefined;
    let avg = scores.reduce((a, b) => a + b, 0) / scores.length;
    return {
      label: `\u2605 ${(Math.round(avg * 10) / 10).toFixed(1)} avg \u00b7 ${scores.length}`,
    };
  };

  isBusyWith = (candidate: Candidate | undefined, verb: string): boolean => {
    return (
      this.isBusyCandidate(candidate) && this.args.tracker.busyVerb === verb
    );
  };

  <template>
    <div class='tab-section pipeline-section'>
      <div class='sec-head'>
        <div class='htext'>
          <h2>Candidate Pipeline</h2>
          <p class='byline'>By stage — screening through offer</p>
        </div>
        {{#if @tracker.canCreate}}
          <Button
            type='button'
            @tone='primary'
            @appearance='accent'
            class='btn-review'
            @loading={{@tracker.addCard.isRunning}}
            {{on 'click' (fn @tracker.addNew Candidate)}}
          >+ Add candidate</Button>
        {{/if}}
      </div>
      <Board
        @boardLabel='Candidate Pipeline'
        @columns={{this.kanbanColumns}}
        @placements={{this.kanbanPlacements}}
        @onChange={{this.handleKanbanChange}}
        @onOpen={{this.openCandidateAt}}
        @cardSize='triple-strip'
      >
        <:card as |placement|>
          {{#let
            (getComponent (this.candidateAt placement.index))
            (this.candidateAt placement.index)
            (this.statusAt placement.index)
            as |CandidateField candidateModel candidateStatus|
          }}
            {{#if CandidateField}}
              <CandidateField @format='fitted' @displayContainer={{false}} />
            {{/if}}
            {{#if (this.hasCardExtras candidateModel)}}
              {{! The kanban drag engine claims every pointerdown inside
                [data-card-index]; stopping propagation here keeps
                button presses from becoming drags or card-opens. }}
              {{! template-lint-disable no-invalid-interactive no-pointer-down-event-binding }}
              <div
                class='card-extras'
                {{on 'pointerdown' this.stopEvent}}
                {{on 'mousedown' this.stopEvent}}
                {{on 'click' this.stopEvent}}
              >
                {{#let
                  (this.pipelineAge candidateModel)
                  (this.avgInterviewScore candidateModel)
                  as |age avg|
                }}
                  {{#if
                    (or
                      (eq candidateStatus 'hired')
                      (eq candidateStatus 'rejected')
                    )
                  }}
                    {{! Terminal stages: nothing left to act on, so
                      only the plain age/score chips apply. }}
                  {{else}}
                    {{#let (@tracker.whoseTurn candidateModel) as |turn|}}
                      <span
                        class='turn-chip turn-{{turn.tone}}'
                      >{{turn.label}}</span>
                    {{/let}}
                  {{/if}}
                  {{#if age}}
                    <span
                      class='age-chip {{if age.stale "stale"}}'
                    >{{age.label}}</span>
                  {{/if}}
                  {{#if avg}}
                    <span class='avg-chip'>{{avg.label}}</span>
                  {{/if}}
                {{/let}}
                {{! No action button at `applied` — résumé extraction
                    is a tool with a resume-text precondition, so it
                    lives on the candidate's detail page, not the
                    board. The board only offers HR's next pipeline
                    move. }}
                {{#if (eq candidateStatus 'screening')}}
                  <Button
                    type='button'
                    @tone='neutral'
                    @appearance='filled'
                    class='stage-act'
                    @disabled={{this.isScheduling candidateModel}}
                    {{on 'click' (fn this.scheduleInterview candidateModel)}}
                  >{{if
                      (this.isScheduling candidateModel)
                      'Scheduling…'
                      'Schedule interview'
                    }}</Button>
                {{/if}}
                {{#if (eq candidateStatus 'interviewing')}}
                  {{#if candidateModel.offerState}}
                    {{! An offer already exists (this card was dragged
                        back, or the data moved around it) — offering
                        "Advance to offer" would create a contradiction
                        and scheduling more rounds past a live offer is
                        not HR's next move. The only affordance is the
                        Offer itself; stage moves happen by drag.
                        Guarded on the offerState scalar, not the
                        `offer` linksTo, for the render-race reason
                        documented on openCandidateOffer. }}
                    <Button
                      type='button'
                      @tone='neutral'
                      @appearance='filled'
                      class='offer-link'
                      {{on 'click' (fn this.openCandidateOffer candidateModel)}}
                    >Offer &middot;
                      {{this.offerLabel candidateModel}}</Button>
                  {{else}}
                    <Button
                      type='button'
                      @tone='neutral'
                      @appearance='filled'
                      class='stage-act'
                      @disabled={{this.isScheduling candidateModel}}
                      {{on 'click' (fn this.scheduleInterview candidateModel)}}
                    >{{if
                        (this.isScheduling candidateModel)
                        'Scheduling…'
                        (if
                          (this.hasUpcomingInterview candidateModel)
                          'Schedule next round'
                          'Schedule interview'
                        )
                      }}</Button>
                    <Button
                      type='button'
                      @tone='primary'
                      @appearance='accent'
                      class='stage-act approve'
                      @disabled={{this.isBusyCandidate candidateModel}}
                      {{on 'click' (fn this.advanceToOffer candidateModel)}}
                    >{{if
                        (this.isBusyWith candidateModel 'create')
                        'Creating draft…'
                        'Advance to offer'
                      }}</Button>
                  {{/if}}
                {{/if}}
                {{#if (eq candidateStatus 'offer')}}
                  {{! Three states, matching the offer lifecycle:
                      1. no offer yet → Create offer (drafts it, no send)
                      2. draft → Edit offer (review terms + letter on the
                         Offer card) and Send offer (the deliberate act)
                      3. sent/answered → status link only; the ball is
                         with the candidate, replies are recorded on the
                         Offer card, hire/reject via drag. }}
                  {{#if (eq candidateModel.offerState 'draft')}}
                    <Button
                      type='button'
                      @tone='neutral'
                      @appearance='filled'
                      class='stage-act'
                      {{on 'click' (fn this.openCandidateOffer candidateModel)}}
                    >Edit offer</Button>
                    <Button
                      type='button'
                      @tone='primary'
                      @appearance='accent'
                      class='stage-act approve'
                      @disabled={{this.isBusyCandidate candidateModel}}
                      {{on 'click' (fn this.extendOffer candidateModel)}}
                    >{{if
                        (this.isBusyWith candidateModel 'send')
                        'Sending…'
                        'Send offer'
                      }}</Button>
                  {{else if candidateModel.offerState}}
                    <Button
                      type='button'
                      @tone='neutral'
                      @appearance='filled'
                      class='offer-link'
                      {{on 'click' (fn this.openCandidateOffer candidateModel)}}
                    >Offer &middot;
                      {{this.offerLabel candidateModel}}</Button>
                  {{else}}
                    <Button
                      type='button'
                      @tone='primary'
                      @appearance='accent'
                      class='stage-act approve'
                      @disabled={{this.isBusyCandidate candidateModel}}
                      {{on 'click' (fn this.advanceToOffer candidateModel)}}
                    >{{if
                        (this.isBusyWith candidateModel 'create')
                        'Creating…'
                        'Create offer'
                      }}</Button>
                  {{/if}}
                {{/if}}
              </div>
            {{/if}}
          {{/let}}
        </:card>
        <:ghost as |dragIdx|>
          {{#let (getComponent (this.candidateAt dragIdx)) as |CandidateField|}}
            {{#if CandidateField}}
              <CandidateField @format='fitted' @displayContainer={{false}} />
            {{/if}}
          {{/let}}
        </:ghost>
      </Board>
    </div>
    <style scoped>
      @container tracker (max-width: 40rem) {
        .page {
          height: auto;
          overflow-y: visible;
        }
      }
      .page {
        background: var(--card);
        padding: var(--boxel-sp-xl) var(--boxel-sp-xxl, 3.5rem)
          var(--boxel-sp-xxxl, 6rem);
        min-width: 0;

        height: 100%;
        overflow-y: auto;
        box-sizing: border-box;
      }
      .sec-head {
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp);
        padding-bottom: var(--boxel-sp);
        border-bottom: 0.125rem solid var(--card-foreground);
        margin: 0 0 var(--boxel-sp-lg);
      }
      .sec-head .htext {
        margin-right: auto;
      }
      .sec-head .htext h2 {
        font-family: var(--font-sans);
        font-weight: 700;
        font-size: 1.25rem;
        margin: 0 0 0.1875rem;
      }
      .sec-head .htext .byline {
        font-family: var(--font-mono);
        font-size: 0.7188rem;
        letter-spacing: 0.02em;
        color: var(--muted-foreground);
        margin: 0;
      }
      .offer-link {
        letter-spacing: 0.03em;
      }
      .offer-link:focus-visible {
        outline: 0.125rem solid var(--primary);
        outline-offset: 0.125rem;
      }
      .card-extras {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 0.375rem;
        padding: 0.375rem 0.625rem 0.5rem;
        cursor: default;
      }
      .age-chip,
      .avg-chip {
        font-family: var(--font-mono);
        font-size: 0.625rem;
        font-weight: 600;
        letter-spacing: 0.03em;
        padding: 0.125rem 0.4375rem;
        background: var(--muted);
        color: var(--muted-foreground);
        font-variant-numeric: tabular-nums;
      }
      .age-chip.stale {
        background: none;
        border: 0.125rem solid var(--primary);
        color: var(--primary-ink);
        border-radius: 0;
        font-weight: 700;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        transform: rotate(-4deg);
        text-shadow: 0.0312rem 0.0312rem 0 var(--primary);
      }
      .turn-chip {
        font-family: var(--font-mono);
        font-size: 0.625rem;
        font-weight: 700;
        letter-spacing: 0.02em;
        padding: 0.125rem 0.4375rem;
        border-radius: 62.4375rem;
      }
      .review {
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        overflow: hidden;
      }
      .review:focus-visible {
        outline: 0.125rem solid var(--primary);
        outline-offset: 0.125rem;
      }
      .stage-act {
        line-height: inherit;
      }
      .stage-act:focus-visible {
        outline: 0.125rem solid var(--primary);
        outline-offset: 0.125rem;
      }
      .stage-act:disabled {
        --button-button-disabled-opacity: 0.6;
        cursor: default;
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
      .btn-review {
        margin-bottom: var(--boxel-sp-5xs);
      }
      .pipeline-section {
        height: 44.375rem;
        display: flex;
        flex-direction: column;
        --boxel-kanban-bg: var(--muted);
        --boxel-kanban-fg: var(--card-foreground);
        --boxel-kanban-card-bg: var(--card);
        --boxel-kanban-card-fg: var(--card-foreground);
        --boxel-kanban-muted-fg: var(--muted-foreground);
        --boxel-kanban-border: var(--border);
      }
      .pipeline-section > .sec-head {
        flex: none;
      }
      .pipeline-section > *:last-child {
        flex: 1;
        min-height: 0;
      }
      .action {
        border: 1px solid currentColor;
        border-radius: 0;
        background: none;
        padding: var(--boxel-sp-5xs) var(--boxel-sp-xs);
        font-family: var(--font-mono);
        font-size: 0.65rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        cursor: pointer;
        transition:
          transform 0.1s ease-out,
          opacity 0.15s ease-out;
      }
      .action:hover:not(:disabled) {
        transform: translateY(-0.0625rem);
      }
      .action:disabled {
        cursor: wait;
        pointer-events: none;
        animation: action-busy-pulse 1s ease-in-out infinite;
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
      @media (prefers-reduced-motion: reduce) {
        .action:disabled {
          animation: none;
          opacity: 0.55;
        }
      }
      .action.approve {
        color: var(--success-ink);
      }
      .action.reject {
        color: var(--destructive-ink);
      }
    </style>
  </template>
}
