import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';

import { EmptyState } from '@cardstack/pretui/components/empty-state';

import { StatePill } from '@cardstack/catalog/components/state-pill';
import type { ContractClause } from '../contract-clause';
import { CLAUSE_TYPE_LABELS } from '../clause';
import { DEVIATION_SEVERITY_HUE } from '../contract-clause';
import type { Hue } from '@cardstack/catalog/components/state-pill';

// Clause Navigator — the table of contents a reviewer actually needs: a
// contract's clauses grouped by type, each row carrying its deviation
// severity so the eye lands on what moved away from standard language
// first. Render-only: the consumer (contract workspace or contract page)
// supplies resolved ContractClause instances and the open callback.

interface Group {
  type: string;
  label: string;
  clauses: ContractClause[];
}

interface Signature {
  Args: {
    clauses: ContractClause[] | undefined;
    onOpen?: (clause: ContractClause) => void;
  };
  Element: HTMLElement;
}

export class ClauseNavigator extends GlimmerComponent<Signature> {
  get clauses(): ContractClause[] {
    return (this.args.clauses ?? []).filter(Boolean);
  }

  get groups(): Group[] {
    let byType = new Map<string, ContractClause[]>();
    for (let clause of this.clauses) {
      let type = clause.clauseType ?? 'other';
      if (!byType.has(type)) {
        byType.set(type, []);
      }
      byType.get(type)!.push(clause);
    }
    return [...byType.entries()].map(([type, clauses]) => ({
      type,
      label: CLAUSE_TYPE_LABELS[type] ?? type,
      clauses,
    }));
  }

  get deviationCount(): number {
    return this.clauses.filter(
      (c) => c.deviationSeverity && c.deviationSeverity !== 'none',
    ).length;
  }

  hueFor = (clause: ContractClause): Hue =>
    (DEVIATION_SEVERITY_HUE[clause.deviationSeverity ?? 'none'] ??
      'slate') as Hue;

  open = (clause: ContractClause) => {
    this.args.onOpen?.(clause);
  };

  get summary() {
    let n = this.clauses.length;
    let d = this.deviationCount;
    return `${n} ${n === 1 ? 'clause' : 'clauses'} · ${d} ${d === 1 ? 'deviates' : 'deviate'} from standard`;
  }

  <template>
    <nav class='navigator' aria-label='Contract clauses' ...attributes>
      {{#if this.clauses.length}}
        <p class='summary'>{{this.summary}}</p>
        {{#each this.groups as |group|}}
          <section class='group'>
            <h3>{{group.label}}</h3>
            <ul>
              {{#each group.clauses as |clause|}}
                <li>
                  <button
                    type='button'
                    class='clause-row'
                    {{on 'click' (fn this.open clause)}}
                  >
                    <span class='clause-name'>{{clause.cardTitle}}</span>
                    <StatePill
                      @label={{clause.deviationSeverity}}
                      @hue={{this.hueFor clause}}
                      @dot={{true}}
                    />
                  </button>
                </li>
              {{/each}}
            </ul>
          </section>
        {{/each}}
      {{else}}
        <EmptyState
          @title='No clauses recorded for this contract yet.'
          @texture={{false}}
          @size='s'
        />
      {{/if}}
    </nav>
    <style scoped>
      .navigator {
        display: grid;
        gap: var(--boxel-sp-sm);
        font-size: var(--boxel-font-size-sm);
      }
      .summary {
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-xs);
        font-variant-numeric: tabular-nums;
      }
      .group h3 {
        margin: 0 0 var(--boxel-sp-5xs);
        font-size: var(--boxel-font-size-xs);
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      ul {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: var(--boxel-sp-6xs);
      }
      .clause-row {
        display: flex;
        justify-content: space-between;
        align-items: center;
        gap: var(--boxel-sp-sm);
        width: 100%;
        text-align: left;
        border: none;
        border-radius: calc(var(--radius) / 1.5);
        background: transparent;
        padding: var(--boxel-sp-4xs) var(--boxel-sp-xs);
        font-family: inherit;
        font-size: inherit;
        font-weight: inherit;
        line-height: inherit;
        color: inherit;
      }
      .clause-row:hover {
        background: var(--muted);
      }
      .clause-name {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
    </style>
  </template>
}
