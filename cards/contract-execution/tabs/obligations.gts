import GlimmerComponent from '@glimmer/component';
import type { ContractExecutionView } from '../contract-execution-app';
import { eq } from '@cardstack/boxel-ui/helpers';
import { DUE_SOON_DAYS, obligationStateLabel } from '../../legal/obligation';
import { StatePill, type Hue } from '../../../components/state-pill';
import { Table } from '../../../components/table';
import {
  OBLIGATION_COLUMNS,
  asAny,
  ObligationGroup,
} from '../contract-execution-data';
interface Signature {
  Args: { app: ContractExecutionView };
}

export class ObligationsTab extends GlimmerComponent<Signature> {
  /**
   * The roll-up above the obligation table.
   *
   * It turns "there are obligations" into "two are late and the oldest is 18
   * days out".
   */
  get obligationKpis() {
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
        unit: '',
        alarm: overdue.length > 0,
        detail: oldest ? `Oldest ${oldest} days past due` : 'Nothing late',
      },
      {
        label: 'Due soon',
        value: soon.length,
        unit: '',
        alarm: false,
        detail: `Inside ${DUE_SOON_DAYS} days`,
      },
      {
        label: 'On track',
        value: ok.length,
        unit: '',
        alarm: false,
        detail: 'Not yet due',
      },
      {
        label: 'Evidence filed',
        value: evidenced.length,
        unit: `/${obs.length}`,
        alarm: false,
        detail: `${obs.length - evidenced.length} unevidenced`,
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

  get obligationGroups(): ObligationGroup[] {
    let by = (...states: string[]) =>
      this.args.app.obligations.filter((o) => states.includes(o.status ?? ''));
    return [
      {
        key: 'overdue',
        label: 'Overdue',
        hue: 'red' as Hue,
        rows: by('overdue'),
      },
      {
        key: 'now',
        label: 'Due now or this week',
        hue: 'orange' as Hue,
        rows: by('due_today', 'due_soon'),
      },
      {
        key: 'ahead',
        label: 'On track',
        hue: 'green' as Hue,
        rows: by('on_track'),
      },
    ].filter((g) => g.rows.length);
  }

  obligationLabelOf = (value?: string | null): string =>
    obligationStateLabel(value);

  obligationHueOf = (state?: string | null): Hue =>
    state === 'overdue'
      ? 'red'
      : state === 'due_today'
        ? 'orange'
        : state === 'due_soon'
          ? 'amber'
          : state === 'closed'
            ? 'slate'
            : 'green';

  <template>
    <section class='cx-sec' aria-label='Obligation tracker'>
      <div class='cx-kpis'>
        {{#each this.obligationKpis as |k|}}
          <div class='cx-kpi'>
            <p class='cx-kpi-l'>{{k.label}}</p>
            <p class='cx-kpi-v {{if k.alarm "is-alarm"}}'>{{k.value}}{{#if
                k.unit
              }}<span class='cx-kpi-u'>{{k.unit}}</span>{{/if}}</p>
            <p class='cx-kpi-d'>{{k.detail}}</p>
          </div>
        {{/each}}
      </div>

      {{#each this.obligationGroups as |g|}}
        <div class='cx-group'>
          <h2 class='cx-h'>
            <StatePill @label={{g.label}} @hue={{g.hue}} @dot={{true}} />
            <span class='cx-count'>{{g.rows.length}}</span>
          </h2>
          <Table
            @columns={{OBLIGATION_COLUMNS}}
            @items={{g.rows}}
            @onRowClick={{@app.openCard}}
            @emptyMessage='Nothing in this band.'
          >
            <:cell as |cellRow column|>{{#let (asAny cellRow) as |row|}}
                {{#if (eq column.key 'status')}}
                  <StatePill
                    @label={{this.obligationLabelOf row.status}}
                    @hue={{this.obligationHueOf row.status}}
                    @dot={{true}}
                  />
                {{else if (eq column.key 'recurrence')}}
                  <span class='cx-scope'>{{this.recurrenceLabel row}}</span>
                {{else if (eq column.key 'evidence')}}
                  {{#if (this.hasEvidence row)}}
                    <StatePill @label='Filed' @hue='green' />
                  {{else if (this.evidenceDue row)}}
                    <StatePill @label='Missing' @hue='red' />
                  {{else}}
                    <span class='cx-none'>not due</span>
                  {{/if}}
                {{/if}}
              {{/let}}</:cell>
          </Table>
        </div>
      {{else}}
        <p class='cx-empty'>No obligations are being tracked yet.</p>
      {{/each}}
    </section>

    <style scoped>
      .cx-sec {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
      }
      .cx-group {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-2xs);
      }
      .cx-h {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-2xs);
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
      }
      .cx-count {
        font-variant-numeric: tabular-nums;
        font-weight: 600;
      }
      .cx-empty {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      .cx-kpi {
        outline: 1px solid var(--border);
        outline-offset: -0.5px;
        padding: var(--boxel-sp-xs) var(--boxel-sp);
        background: var(--background);
        min-width: 0;
      }
      .cx-kpi-l {
        margin: 0;
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .cx-kpi-v {
        margin: var(--boxel-sp-4xs) 0 0;
        font-family: var(--font-mono);
        font-variant-numeric: tabular-nums;
        font-size: 1.9rem;
        font-weight: 650;
        line-height: 1.1;
        letter-spacing: -0.02em;
      }
      .cx-kpi-v.is-alarm {
        color: var(--destructive-ink);
      }
      .cx-kpi-v.is-none {
        color: var(--muted-foreground);
      }
      .cx-kpi-u {
        font-size: 0.95rem;
        font-weight: 500;
        color: var(--muted-foreground);
      }
      .cx-kpi-d {
        margin: var(--boxel-sp-5xs) 0 0;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
        line-height: 1.4;
      }
      .cx-none {
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-sm);
      }
      .cx-scope {
        font-size: var(--boxel-font-size-sm);
      }
      .cx-kpis {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(10.5rem, 1fr));
        /* Each tile draws its own rule, so a short last row leaves no
           rule-coloured gap behind it. */
        gap: 0;
        margin-bottom: var(--boxel-sp);
      }
      .cx-kpis > .cx-kpi:first-child {
        padding-left: 0;
      }
      .cx-kpi {
        background: var(--background);
        padding: var(--boxel-sp-xs) var(--boxel-sp);
      }
      .cx-kpi.is-alarm {
        --stat-value-color: var(--destructive-ink);
        color: var(--destructive-ink);
      }
    </style>
  </template>
}
