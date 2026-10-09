import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  linksToMany,
  StringField,
} from '@cardstack/base/card-api';
import HeadsetIcon from '@cardstack/boxel-icons/headset';

import {
  Case,
  SEVERITY_HUES,
} from '@cardstack/catalog/cards/service-desk/case';
import { Escalation } from '@cardstack/catalog/cards/service-desk/escalation';
import { Sla } from '@cardstack/catalog/cards/service-desk/sla';
import { Workflow } from '@cardstack/catalog/cards/service-desk/workflow';
import {
  sortByUrgency,
  timerSnapshot,
} from '@cardstack/catalog/cards/service-desk/utils/sla';
import {
  CommandCenter,
  type BreachRiskRow,
} from '../components/command-center';
import { CrossRecordTimeline } from '../components/cross-record-timeline';
import { SupportQueue, type QueueRow } from '../components/support-queue';
import { WorkflowBoard, type BoardCard } from '../components/workflow-board';
import type { DashboardTile } from '@cardstack/catalog/components/dashboard';
import {
  WorkspaceHome,
  type HomeRail,
} from '../../../components/workspace-home';
import {
  RelatedRecords,
  type RelatedRecord,
} from '../../../components/related-records';

// Usage page for the case desk blocks: real Cases, their SLA and escalations,
// and the support Workflow, joined the way a desk app joins them and handed to
// each block. Moves on the board are refused, since an example never edits
// the cards it shows.
export class CaseDeskExample extends CardDef {
  static displayName = 'Case Desk Example';
  static icon = HeadsetIcon;

  @field cases = linksToMany(() => Case);
  @field slas = linksToMany(() => Sla);
  @field escalations = linksToMany(() => Escalation);
  @field workflow = linksTo(() => Workflow);
  @field operatorName = contains(StringField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: CaseDeskExample) {
      return 'Case desk blocks over the payments cases';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get cases(): Case[] {
      return (this.args.model.cases ?? []).filter(Boolean) as Case[];
    }
    get slas(): Sla[] {
      return (this.args.model.slas ?? []).filter(Boolean) as Sla[];
    }
    get escalations(): Escalation[] {
      return (this.args.model.escalations ?? []).filter(
        Boolean,
      ) as Escalation[];
    }
    get operator(): string {
      return this.args.model.operatorName || 'the operator';
    }

    open = (card: any) => {
      if (card?.id) {
        (this.args as any).viewCard?.(new URL(card.id));
      }
    };

    refuseMove = async () => {
      throw new Error('Moves are switched off in this example.');
    };

    worstFacts = (card: Case) => {
      let sla = this.slas.find((s) => s.subjectId === card.id);
      let timers = (sla?.timers ?? []).filter((t: any) => !t.satisfiedAt);
      return timers.length ? sortByUrgency(timers)[0] : undefined;
    };

    get openCases(): Case[] {
      return this.cases.filter(
        (c) => c.status !== 'resolved' && c.status !== 'closed',
      );
    }

    get breachRisk() {
      let rows = this.openCases
        .map((card) => ({ card, facts: this.worstFacts(card) }))
        .filter((r): r is { card: Case; facts: any } => Boolean(r.facts));
      return sortByUrgency(rows, (r) => r.facts);
    }

    get openEscalations(): Escalation[] {
      return this.escalations.filter((e) => e.status === 'open');
    }

    label = (c: Case) =>
      `${c.caseId?.value ? c.caseId.value + ' · ' : ''}${c.cardTitle ?? ''}`;

    get tiles(): DashboardTile[] {
      let states = this.breachRisk.map((r) => timerSnapshot(r.facts).state);
      let atRisk = states.filter((s) => s === 'urgent' || s === 'warning');
      let breached = states.filter((s) => s === 'breached');
      return [
        { label: 'open cases', value: this.openCases.length },
        {
          label: '≥ 75% consumed',
          value: atRisk.length,
          intent: atRisk.length ? 'amber' : 'neutral',
        },
        {
          label: 'breached',
          value: breached.length,
          intent: breached.length ? 'red' : 'neutral',
        },
        {
          label: 'awaiting ack',
          value: this.openEscalations.length,
          intent: this.openEscalations.length ? 'amber' : 'neutral',
        },
      ] as DashboardTile[];
    }

    get breachRows(): BreachRiskRow[] {
      return this.breachRisk.map(({ card, facts }) => ({
        card,
        label: this.label(card),
        timerFacts: facts,
        chipLabel: card.severity ?? undefined,
        chipHue: SEVERITY_HUES[card.severity ?? 'low'] ?? 'slate',
        ownerName: card.ownership?.ownerName ?? undefined,
        clockKind: facts?.kind,
      })) as BreachRiskRow[];
    }

    get queues() {
      let byTeam = new Map<string, number>();
      for (let c of this.openCases) {
        let team = c.ownership?.teamName ?? 'Unrouted';
        byTeam.set(team, (byTeam.get(team) ?? 0) + 1);
      }
      return [...byTeam.entries()].map(([name, open]) => ({
        name,
        open,
        agents: 2,
        overloaded: open > 8,
        oldestLabel: open > 8 ? 'heavy' : 'ok',
      }));
    }

    get acks() {
      return this.openEscalations.map((e) => ({
        levelKey: (e.toLevel?.key as string) ?? '?',
        label: e.subjectTitle ?? e.cardTitle ?? '?',
        ackDueLabel: e.toLevel?.ackTargetMinutes
          ? `${e.toLevel.ackTargetMinutes}m target`
          : 'no target',
        overdue: e.ackOverdue === 'yes',
        onOpen: () => this.open(e),
      }));
    }

    get queueRows(): QueueRow[] {
      return this.openCases.map((c) => ({
        card: c,
        label: this.label(c),
        timerFacts: this.worstFacts(c),
        chipLabel: c.severity ?? undefined,
        chipHue: SEVERITY_HUES[c.severity ?? 'low'] ?? 'slate',
        ownerName: c.ownership?.ownerName ?? undefined,
      })) as QueueRow[];
    }

    get boardCards(): BoardCard[] {
      return this.cases
        .filter((c) => c.status !== 'closed')
        .map((c) => ({
          card: c,
          label: c.caseId?.value ?? undefined,
          title: c.cardTitle ?? undefined,
          chipLabel: c.severity ?? undefined,
          chipHue: SEVERITY_HUES[c.severity ?? 'low'] ?? 'slate',
          ownerName: c.ownership?.ownerName ?? undefined,
          stateKey: c.workflowState?.key ?? undefined,
          timerFacts: this.worstFacts(c),
        }));
    }

    get homeRails(): HomeRail[] {
      return [
        {
          title: 'Awaiting acknowledgement',
          emptyLabel: 'Every escalation acknowledged.',
          items: this.openEscalations.map((e) => ({
            label: e.subjectTitle ?? e.cardTitle ?? '?',
            meta: e.toLevel?.ackTargetMinutes
              ? `${e.toLevel.ackTargetMinutes}m target`
              : undefined,
            onOpen: () => this.open(e),
          })),
        },
        {
          title: 'Breaching soon',
          emptyLabel: 'No clocks at risk.',
          items: this.breachRisk.slice(0, 4).map(({ card, facts }) => ({
            label: card.cardTitle ?? '',
            meta: timerSnapshot(facts).shortLabel,
            onOpen: () => this.open(card),
          })),
        },
      ];
    }

    get escalationEvents() {
      return this.escalations.map((e) => ({
        at: e.raisedAt ?? undefined,
        label: `${e.cardTitle ?? 'Escalation'} on ${e.subjectTitle ?? '?'}`,
        by: e.raisedByName ?? undefined,
        intent:
          e.status === 'open'
            ? ('amber' as const)
            : e.status === 'cancelled'
              ? ('slate' as const)
              : ('green' as const),
      }));
    }

    get related(): RelatedRecord[] {
      let first = this.openCases[0];
      if (!first) {
        return [];
      }
      return [
        ...(first.relatedTickets ?? []).filter(Boolean).map((t) => ({
          card: t as CardDef,
          relationship: 'raised from',
        })),
        ...this.escalations
          .filter((e) => e.subjectId === first.id)
          .map((e) => ({
            card: e as CardDef,
            relationship: 'escalated to',
            detail: e.status ?? undefined,
            emphasis: e.status === 'open',
          })),
        ...this.slas
          .filter((s) => s.subjectId === first.id)
          .map((s) => ({ card: s as CardDef, relationship: 'measured by' })),
      ];
    }

    <template>
      <div class='demo'>
        <section>
          <h2>Command Center</h2>
          <CommandCenter
            @tiles={{this.tiles}}
            @breachRows={{this.breachRows}}
            @queues={{this.queues}}
            @escalations={{this.acks}}
            @onOpenCard={{this.open}}
            @operatorName={{this.operator}}
            @agentsOnDuty={{2}}
            @openCount={{this.openCases.length}}
          />
        </section>
        <section>
          <h2>Workspace Home</h2>
          <WorkspaceHome
            @greeting='Morning, {{this.operator}}'
            @identity='on duty'
            @rails={{this.homeRails}}
          />
        </section>
        <section>
          <h2>Support Queue</h2>
          <SupportQueue @rows={{this.queueRows}} @onOpen={{this.open}} />
        </section>
        {{#if @model.workflow}}
          <section>
            <h2>Workflow Board — moves are refused here</h2>
            <WorkflowBoard
              @workflow={{@model.workflow}}
              @cards={{this.boardCards}}
              @onMove={{this.refuseMove}}
              @onOpen={{this.open}}
            />
          </section>
        {{/if}}
        <section>
          <h2>Cross-Record Timeline — escalations</h2>
          <CrossRecordTimeline @events={{this.escalationEvents}} />
        </section>
        <section>
          <h2>Related Records — the first open case</h2>
          <RelatedRecords @records={{this.related}} @onOpen={{this.open}} />
        </section>
      </div>
      <style scoped>
        .demo {
          padding: var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp-xl);
        }
        section {
          display: grid;
          gap: var(--boxel-sp-sm);
          min-width: 0;
        }
        h2 {
          margin: 0;
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='row'>
        <HeadsetIcon class='ic' />
        <span class='name'>{{@model.cardTitle}}</span>
      </div>
      <style scoped>
        .row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .ic {
          width: 1.125rem;
          height: 1.125rem;
          flex: none;
        }
        .name {
          font-weight: 600;
        }
      </style>
    </template>
  };
}
