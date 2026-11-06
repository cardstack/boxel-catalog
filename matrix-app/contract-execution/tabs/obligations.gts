import GlimmerComponent from '@glimmer/component';
import type { ContractExecutionView } from '../contract-execution-app';
import { DUE_SOON_DAYS, obligationStateLabel } from '../../legal/obligation';
import { formatDay, humanise, type Tone } from '../contract-execution-data';
import {
  Block,
  CeTable,
  Dot,
  StatStrip,
  type Col,
  type Stat,
} from '../components';

interface Signature {
  Args: { app: ContractExecutionView };
}

// The tab's own four numbers, drawn under the desk strip by the shell.
export class ObligationStats extends GlimmerComponent<Signature> {
  get obligationKpis(): Stat[] {
    let obs: any[] = this.args.app.obligations;
    let overdue = obs.filter(
      (o) => o.status === 'overdue' || o.status === 'due_today',
    );
    let soon = obs.filter((o) => o.status === 'due_soon');
    let ok = obs.filter((o) => o.status === 'on_track');
    let evidenced = obs.filter((o) =>
      (o.completions ?? []).some((c: any) => c?.evidenceUrl),
    );
    let oldest = Math.max(0, ...overdue.map((o) => o.isOverdue ?? 0));
    return [
      {
        label: 'Overdue',
        value: overdue.length,
        tone: (overdue.length ? 'bad' : 'neutral') as Tone,
        sub: oldest ? `Oldest ${oldest} days past due` : 'Nothing late',
      },
      {
        label: 'Due soon',
        value: soon.length,
        tone: 'warn' as Tone,
        sub: `Inside ${DUE_SOON_DAYS} days`,
      },
      {
        label: 'On track',
        value: ok.length,
        tone: 'ok' as Tone,
        sub: 'Not yet due',
      },
      {
        label: 'Evidence filed',
        value: evidenced.length,
        unit: `/${obs.length}`,
        sub: `${obs.length - evidenced.length} unevidenced`,
      },
    ];
  }

  /** Reads the catalog RecurringPatternField's own vocabulary, not a re-derivation. */
  recurrenceLabel = (o: any): string => {
    let p = o?.recurrence?.pattern;
    if (!p || p === 'none') return 'One time';
    let every = o?.recurrence?.interval;
    return every && every > 1 ? `Every ${every} ${p}` : p;
  };

  hasEvidence = (o: any): boolean =>
    (o?.completions ?? []).some((c: any) => c?.evidenceUrl);

  /** Evidence is only "missing" once the thing was actually due. */
  evidenceDue = (o: any): boolean =>
    o?.status === 'overdue' ||
    o?.status === 'due_today' ||
    Boolean(o?.closedAt);

  // ---- obligations --------------------------------------------------------

  <template>
    <StatStrip @stats={{this.obligationKpis}} @label='Obligations summary' />
  </template>
}

function stateTone(state?: string | null): Tone {
  return state === 'overdue' || state === 'due_today'
    ? 'bad'
    : state === 'due_soon'
      ? 'warn'
      : state === 'closed'
        ? 'neutral'
        : 'ok';
}

export class ObligationsTab extends GlimmerComponent<Signature> {
  recurrenceLabel = (o: any): string => {
    let p = o?.recurrence?.pattern;
    if (!p || p === 'none') return 'One time';
    let every = o?.recurrence?.interval;
    return every && every > 1 ? `Every ${every} ${p}` : humanise(p);
  };

  hasEvidence = (o: any): boolean =>
    (o?.completions ?? []).some((c: any) => c?.evidenceUrl);

  evidenceDue = (o: any): boolean =>
    o?.status === 'overdue' ||
    o?.status === 'due_today' ||
    Boolean(o?.closedAt);

  columns: Col[] = [
    { label: 'Obligation', kind: 'title', value: (o) => o.cardTitle },
    {
      label: 'Contract',
      kind: 'mono',
      value: (o) => o.contract?.contractNumber ?? o.contract?.cardTitle ?? '—',
    },
    { label: 'Type', value: (o) => humanise(o.obligationType) },
    { label: 'Recurrence', value: (o) => this.recurrenceLabel(o) },
    {
      label: 'State',
      kind: 'dot',
      value: (o) => obligationStateLabel(o.status),
      tone: (o) => stateTone(o.status),
    },
    {
      label: 'Due',
      kind: 'mono',
      align: 'end',
      value: (o) => formatDay(o.nextDueDate),
    },
    {
      label: 'Owner',
      value: (o) => o.owner?.name ?? o.owner?.cardTitle ?? '—',
    },
    { label: 'Evidence', kind: 'custom', align: 'end' },
  ];

  get groups() {
    let all = this.args.app.search(this.args.app.obligations as any[], (o) => [
      o.cardTitle,
      o.contract?.cardTitle,
    ]);
    let by = (...states: string[]) =>
      all.filter((o) => states.includes(o.status ?? ''));
    return [
      { label: 'Overdue', tone: 'bad' as Tone, rows: by('overdue') },
      {
        label: 'Due now or this week',
        tone: 'warn' as Tone,
        rows: by('due_today', 'due_soon'),
      },
      { label: 'On track', tone: 'ok' as Tone, rows: by('on_track') },
    ].filter((g) => g.rows.length);
  }

  <template>
    {{#each this.groups as |g|}}
      <Block>
        <h2 class='ob-head'><Dot @tone={{g.tone}} @label={{g.label}} />
          <span class='ob-n'>{{g.rows.length}}</span></h2>
        <CeTable
          @label={{g.label}}
          @columns={{this.columns}}
          @rows={{g.rows}}
          @onOpen={{@app.openCard}}
        >
          <:cell as |o|>
            {{#if (this.hasEvidence o)}}
              <Dot @tone='ok' @label='Filed' />
            {{else if (this.evidenceDue o)}}
              <Dot @tone='bad' @label='Missing' />
            {{else}}
              <span class='ob-muted'>not due</span>
            {{/if}}
          </:cell>
        </CeTable>
      </Block>
    {{else}}
      <Block>
        <p class='ob-empty'>No obligations tracked yet.</p>
      </Block>
    {{/each}}
    <style scoped>
      .ob-head {
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-3xs);
        margin: 0;
        padding: var(--boxel-sp-xs);
        border-bottom: 1px solid var(--border);
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .ob-n {
        font-family: var(--font-mono);
        font-weight: 400;
        color: var(--muted-foreground);
      }
      .ob-muted {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .ob-empty {
        margin: 0;
        padding: var(--boxel-sp-xs);
        color: var(--muted-foreground);
      }
    </style>
  </template>
}
