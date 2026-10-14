import GlimmerComponent from '@glimmer/component';
import type { ContractExecutionView } from '../contract-execution-app';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Clause } from '../../legal/clause';
import { CollectionPanel } from '../../../components/collection-panel';
import { StatePill, type Hue } from '../../../components/state-pill';
import { humanise, CLAUSE_COLUMNS, asAny } from '../contract-execution-data';
interface Signature {
  Args: { app: ContractExecutionView };
}

export class ClausesTab extends GlimmerComponent<Signature> {
  clauseRiskLabel = (r?: string | null): string => humanise(r);

  clauseRiskHue = (r?: string | null): Hue =>
    r === 'critical'
      ? 'red'
      : r === 'high'
        ? 'orange'
        : r === 'medium'
          ? 'amber'
          : 'green';

  /** How many contracts use this standard clause, and how many deviate. */
  clauseUsage = (clauseId?: string) => {
    if (!clauseId) return { used: 0, deviations: 0 };
    let rows = this.args.app.clauseUses.filter(
      (u: any) => u?.standardClause?.id === clauseId,
    );
    return {
      used: rows.length,
      deviations: rows.filter((u: any) => u?.isDeviation).length,
    };
  };

  <template>
    <CollectionPanel
      @cardClass={{Clause}}
      @context={{@app.context}}
      @realms={{@app.realmList}}
      @columns={{CLAUSE_COLUMNS}}
      @label='Clause library'
      @searchPlaceholder='Search approved language…'
      @newLabel='clause'
      @defaultView='table'
      @sortBy='name'
    >
      <:cell as |cellRow column|>{{#let (asAny cellRow) as |row|}}
          {{#if (eq column.key 'riskLevel')}}
            <StatePill
              @label={{this.clauseRiskLabel row.riskLevel}}
              @hue={{this.clauseRiskHue row.riskLevel}}
              @dot={{true}}
            />
          {{else if (eq column.key 'usedIn')}}
            {{#let (this.clauseUsage row.id) as |u|}}
              {{#if u.used}}
                <span class='cx-fig'>{{u.used}}</span>
              {{else}}
                <span class='cx-none'>unused</span>
              {{/if}}
            {{/let}}
          {{else if (eq column.key 'deviations')}}
            {{#let (this.clauseUsage row.id) as |u|}}
              {{#if u.deviations}}
                <StatePill @label='{{u.deviations}}' @hue='red' />
              {{else if u.used}}
                <span class='cx-none'>none</span>
              {{else}}
                <span class='cx-none'>—</span>
              {{/if}}
            {{/let}}
          {{/if}}
        {{/let}}</:cell>
    </CollectionPanel>

    <p class='cx-blocked'>
      <span class='cx-blocked-l'>Not yet available</span>
      Clauses are added by hand for now. Reading a contract's text and proposing
      its clauses automatically is not switched on in this workspace.</p>

    <style scoped>
      .cx-blocked {
        margin: var(--boxel-sp) 0 0;
        padding: var(--boxel-sp-xs) var(--boxel-sp);
        background: var(
          --_cx-sunk,
          color-mix(in oklch, currentColor 4%, transparent)
        );
        color: var(--foreground);
        border-left: 3px solid var(--muted-foreground);
        border-radius: 0 var(--radius) var(--radius) 0;
        font-size: var(--boxel-font-size-sm);
        line-height: 1.55;
        max-width: var(--_cx-measure);
      }
      .cx-blocked-l {
        display: block;
        margin-bottom: var(--boxel-sp-4xs);
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }

      .cx-fig {
        font-family: var(--font-mono);
        font-variant-numeric: tabular-nums;
        font-weight: 650;
      }
      .cx-fig.is-money {
        white-space: nowrap;
      }
      .cx-none {
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-sm);
      }
    </style>
  </template>
}
