import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  StringField,
} from 'https://cardstack.com/base/card-api';
import NumberField from 'https://cardstack.com/base/number';
import BooleanField from 'https://cardstack.com/base/boolean';
import enumField from 'https://cardstack.com/base/enum';
import ShieldCheckIcon from '@cardstack/boxel-icons/shield-check';
import TargetIcon from '@cardstack/boxel-icons/target';
import ClockIcon from '@cardstack/boxel-icons/clock';
import SirenIcon from '@cardstack/boxel-icons/siren';
import { modifier } from 'ember-modifier';
import { guidFor } from '@ember/object/internals';
import { Table } from '@cardstack/pretui/components/table';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { StatePill } from '@cardstack/catalog/components/state-pill';

import { Schedule } from './schedule';
import { TicketPriorityField, ticketPriorityFactor } from './ticket-taxonomy';
import { formatMinutes, ALWAYS_ON, type BusinessSchedule } from './utils/sla';

export const CONDITION_OPERATORS = ['is', 'is not', 'contains'] as const;

// `customerTier` reads as a field name; "Customer tier" reads as a sentence.
// The condition title is the only place an administrator gets to check that a
// policy still matches what they meant, so it is written in their words.
function humanize(attribute: string): string {
  let spaced = attribute.replace(/([a-z0-9])([A-Z])/g, '$1 $2').toLowerCase();
  return spaced.charAt(0).toUpperCase() + spaced.slice(1);
}

const OperatorField = enumField(StringField, {
  displayName: 'Operator',
  options: CONDITION_OPERATORS as unknown as string[],
});

/**
 * One clause of "when does this policy apply".
 *
 * Stored as three readable parts rather than an expression string, so the
 * isolated view can render "Customer tier is VIP" as a chip an administrator
 * can check at a glance. A policy nobody can verify by looking at it is a
 * policy that quietly stops matching.
 */
export class PolicyConditionField extends FieldDef {
  static displayName = 'Condition';

  @field attribute = contains(StringField, {
    description: 'e.g. customerTier, priority, categoryName, channel',
  });
  @field operator = contains(OperatorField);
  @field value = contains(StringField);

  @field title = contains(StringField, {
    computeVia: function (this: PolicyConditionField) {
      if (!this.attribute) {
        return 'Any ticket';
      }
      return `${humanize(this.attribute)} ${this.operator ?? 'is'} ${this.value ?? '—'}`;
    },
  });

  matches(subject: Record<string, unknown>): boolean {
    if (!this.attribute) {
      return true;
    }
    let actual = String(subject[this.attribute] ?? '').toLowerCase();
    let expected = String(this.value ?? '').toLowerCase();
    switch (this.operator) {
      case 'is not':
        return actual !== expected;
      case 'contains':
        return actual.includes(expected);
      default:
        return actual === expected;
    }
  }

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='cond'>{{@model.title}}</span>
      <style scoped>
        .cond {
          display: inline-flex;
          padding: 0.1em 0.5em;
          border: 1px solid var(--border);
          border-radius: 999px;
          background-color: var(--muted);
          color: var(--foreground);
          font-size: var(--boxel-font-size-xs);
          white-space: nowrap;
        }
      </style>
    </template>
  };
}

/**
 * The committed time for one metric, before priority scaling.
 *
 * A policy states ONE target per metric and lets each priority's factor scale
 * it — a P1 gets a quarter, a P4 gets double. Stating all four explicitly is
 * how a policy ends up with a P3 that resolves faster than a P2 after somebody
 * edits one row.
 */
export class SlaTargetField extends FieldDef {
  static displayName = 'SLA Target';

  @field metric = contains(
    enumField(StringField, {
      displayName: 'Metric',
      options: ['First response', 'Next response', 'Resolution'],
    }),
  );
  @field baseMinutes = contains(NumberField, {
    description: 'Target for a P3 ticket, in minutes. Other priorities scale.',
  });

  @field title = contains(StringField, {
    computeVia: function (this: SlaTargetField) {
      return `${this.metric ?? 'Target'} — ${
        typeof this.baseMinutes === 'number'
          ? formatMinutes(this.baseMinutes)
          : '—'
      }`;
    },
  });

  minutesFor(priority?: string | null): number | undefined {
    if (typeof this.baseMinutes !== 'number') {
      return undefined;
    }
    return Math.round(this.baseMinutes * ticketPriorityFactor(priority));
  }

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='tgt'>
        <span class='tgt-metric'>{{@model.metric}}</span>
        <span class='tgt-value'>{{@model.title}}</span>
      </span>
      <style scoped>
        .tgt {
          display: inline-flex;
          gap: var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-xs);
        }
        .tgt-metric {
          color: var(--muted-foreground);
        }
        .tgt-value {
          font-weight: 600;
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };
}

/**
 * Pret UI's `Table` has no caption slot, so the matrix is named by the
 * heading above it: this points the rendered `<table>` at that heading.
 */
const labelledBy = modifier((element: HTMLElement, [id]: [string]) => {
  element.querySelector('table')?.setAttribute('aria-labelledby', id);
});

interface MatrixRow {
  priority: string;
  cells: string[];
}

/**
 * A set of commitments and the conditions under which they apply.
 *
 * The Domain Layers row for SLA Policy has nothing behind it, and neither do
 * SLA Window or Compute SLA Deadline — this card plus `SlaTimerField` plus
 * `utils/sla` are the first implementation of all three.
 */
export class SlaPolicy extends CardDef {
  static displayName = 'SLA Policy';
  static icon = ShieldCheckIcon;

  @field name = contains(StringField);
  @field conditions = containsMany(PolicyConditionField);
  @field targets = containsMany(SlaTargetField);
  @field businessHours = linksTo(() => Schedule);
  @field breachActions = containsMany(StringField, {
    description: 'Fired in order when a target is missed.',
  });
  @field isDefault = contains(BooleanField);
  @field samplePriority = contains(TicketPriorityField, {
    description: 'Only drives the preview in the editor.',
  });

  @field title = contains(StringField, {
    computeVia: function (this: SlaPolicy) {
      return this.name?.trim() || 'Untitled policy';
    },
  });

  @field conditionSummary = contains(StringField, {
    computeVia: function (this: SlaPolicy) {
      let parts = (this.conditions ?? []).map((c) => c.title).filter(Boolean);
      return parts.length ? parts.join(' and ') : 'Any ticket';
    },
  });

  // Denormalized for tiles: 'P1 15m / 2h'. A prerendered view can walk
  // containsMany, but it cannot do the priority arithmetic and stay readable.
  @field targetSummary = contains(StringField, {
    computeVia: function (this: SlaPolicy) {
      let first = (this.targets ?? []).find(
        (t) => t.metric === 'First response',
      );
      let resolve = (this.targets ?? []).find((t) => t.metric === 'Resolution');
      let f = first?.minutesFor('P1');
      let r = resolve?.minutesFor('P1');
      if (f == null && r == null) {
        return 'No targets set';
      }
      return `P1 ${f == null ? '—' : formatMinutes(f)} / ${
        r == null ? '—' : formatMinutes(r)
      }`;
    },
  });

  // Flattened, because a prerendered fitted view resolves no links and
  // READING through one there throws rather than returning undefined — which
  // is how a tile becomes a red error card instead of a slightly emptier tile.
  @field businessHoursSummary = contains(StringField, {
    computeVia: function (this: SlaPolicy) {
      return this.businessHours?.summary ?? 'Always on';
    },
  });

  @field breachActionSummary = contains(StringField, {
    computeVia: function (this: SlaPolicy) {
      let n = (this.breachActions ?? []).filter(Boolean).length;
      return n === 0 ? 'none' : n === 1 ? '1 action' : `${n} actions`;
    },
  });

  /** Does this policy apply to a ticket with these attributes? */
  applies(subject: Record<string, unknown>): boolean {
    let conditions = (this.conditions ?? []).filter((c) => c?.attribute);
    if (!conditions.length) {
      return true;
    }
    return conditions.every((c) => c.matches(subject));
  }

  targetFor(metric: string, priority?: string | null): number | undefined {
    return (this.targets ?? [])
      .find((t) => t.metric === metric)
      ?.minutesFor(priority);
  }

  get schedule(): BusinessSchedule {
    return this.businessHours?.businessSchedule ?? ALWAYS_ON;
  }

  static isolated = class Isolated extends Component<typeof this> {
    targetsId = `sla-targets-${guidFor(this)}`;

    get matrix(): MatrixRow[] {
      let model = this.args.model;
      let metrics = ['First response', 'Resolution'];
      return ['P1', 'P2', 'P3', 'P4'].map((priority) => ({
        priority,
        cells: metrics.map((metric) => {
          let minutes = model?.targetFor?.(metric, priority);
          return minutes == null ? '—' : formatMinutes(minutes);
        }),
      }));
    }

    <template>
      <article class='iso'>
        <header class='iso-head'>
          <div>
            <h1>{{@model.title}}</h1>
            <p class='iso-sub'>{{@model.conditionSummary}}</p>
          </div>
          {{#if @model.isDefault}}
            <StatePill @label='Fallback policy' @hue='slate' />
          {{/if}}
        </header>

        <section class='sect'>
          <h2><TargetIcon class='sec-icon' role='presentation' />Applies when</h2>
          {{#if @model.conditions.length}}
            <div class='chips'>
              {{#each @fields.conditions as |Condition|}}
                <Condition />
              {{/each}}
            </div>
          {{else}}
            <EmptyState
              class='empty'
              @title='No conditions'
              @message='This policy matches every ticket. Only one policy should be this permissive, and it should be the fallback.'
              @texture={{false}}
            />
          {{/if}}
        </section>

        <section class='sect'>
          <h2 id={{this.targetsId}}><TargetIcon
              class='sec-icon'
              role='presentation'
            />Targets</h2>
          <Table class='matrix' {{labelledBy this.targetsId}}>
            <:head>
              <tr>
                <th scope='col'>Priority</th>
                <th scope='col'>First response</th>
                <th scope='col'>Resolution</th>
              </tr>
            </:head>
            <:body>
              {{#each this.matrix as |row|}}
                <tr>
                  <th scope='row'>{{row.priority}}</th>
                  {{#each row.cells as |cell|}}
                    <td>{{cell}}</td>
                  {{/each}}
                </tr>
              {{/each}}
            </:body>
          </Table>
          <p class='note'>One target per metric, scaled by each priority's
            factor. Stating all four by hand is how a P3 ends up resolving
            faster than a P2.</p>
        </section>

        <section class='sect'>
          <h2><ClockIcon class='sec-icon' role='presentation' />Clock runs on</h2>
          {{#if @model.businessHours}}
            <@fields.businessHours @format='embedded' />
          {{else}}
            <EmptyState
              class='empty'
              @title='No schedule linked'
              @message='The clock ticks around the clock, including weekends and holidays.'
              @texture={{false}}
            />
          {{/if}}
        </section>

        <section class='sect'>
          <h2><SirenIcon class='sec-icon' role='presentation' />On breach</h2>
          {{#if @model.breachActions.length}}
            <ol class='actions'>
              {{! Not `as |action|`: in a strict-mode template `action`
                  resolves as the classic action helper, which does not exist
                  there — it fails the prerender outright and renders an empty
                  list in the live view. }}
              {{#each @model.breachActions as |breachAction|}}
                <li>{{breachAction}}</li>
              {{/each}}
            </ol>
          {{else}}
            <EmptyState
              class='empty'
              @title='Nothing happens on breach'
              @message='The target is a measurement, not a commitment, until something acts on it.'
              @texture={{false}}
            />
          {{/if}}
        </section>
      </article>

      <style scoped>
        .iso {
          container-name: iso;
          container-type: inline-size;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
          padding: var(--boxel-sp-lg);
          min-height: 100%;
        }
        .iso-head {
          display: flex;
          justify-content: space-between;
          gap: var(--boxel-sp);
          align-items: flex-start;
          padding-bottom: var(--boxel-sp);
          border-bottom: 1px solid var(--border);
        }
        .iso-head h1 {
          margin: 0;
          font-size: var(--boxel-font-size-lg);
          font-weight: 700;
          letter-spacing: -0.01em;
        }
        .iso-sub {
          margin: 0;
          color: var(--muted-foreground);
          font-size: var(--boxel-font-size-sm);
        }
        .sect {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
        }
        .sect h2 {
          display: flex;
          align-items: center;
          gap: 0.375rem;
          margin: 0;
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        /* Rule 5: one icon per section header, quiet by design — muted colour and
           ~1em with a px floor, so it identifies the section without competing
           with it. Same size in every header, which is what makes the card
           scannable by shape on a second visit. */
        .sec-icon {
          width: max(0.875rem, 1em);
          height: max(0.875rem, 1em);
          flex: 0 0 auto;
          color: var(--muted-foreground);
        }
        .chips {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
        }
        /* Pret UI Table: its header band, zebra rows and hover. It sizes to
           its content like the old matrix, and its numbers stay tabular. The
           P1–P4 row headers are th cells, which Table styles as its sticky,
           mono, uppercase header band; these rules put them back to body
           cells in bold. */
        .matrix {
          align-self: flex-start;
          font-variant-numeric: tabular-nums;
        }
        .matrix :deep(tbody th) {
          position: static;
          height: auto;
          padding: 0.5rem 0.625rem;
          font-family: inherit;
          font-size: inherit;
          font-weight: 700;
          letter-spacing: normal;
          text-transform: none;
          color: var(--foreground);
          background-color: transparent;
          box-shadow: inset 0 -1px 0 var(--border);
        }
        .matrix :deep(tbody tr:nth-child(even) th) {
          background-color: var(--stripe);
        }
        .matrix :deep(tbody tr:hover th) {
          background-color: var(--hover);
        }
        .actions {
          margin: 0;
          padding-left: 1.2rem;
          font-size: var(--boxel-font-size-sm);
        }
        /* Pret UI EmptyState, tuned through its spacing and title knobs to a
           compact well beside the section text. */
        .empty {
          --space-9: 1rem;
          --space-6: 1rem;
          --text-heading: var(--boxel-font-size);
        }
        .note {
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          max-width: 62ch;
          line-height: 1.6;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='emb'>
        <span class='emb-name'>{{@model.title}}</span>
        <span class='emb-cond'>{{@model.conditionSummary}}</span>
        <span class='emb-tgt'>{{@model.targetSummary}}</span>
      </div>
      <style scoped>
        .emb {
          display: flex;
          flex-direction: column;
          gap: 0.125rem;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius);
          background-color: var(--card);
          color: var(--card-foreground);
        }
        .emb-name {
          font-weight: 700;
          font-size: var(--boxel-font-size-sm);
        }
        .emb-cond {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .emb-tgt {
          font-size: var(--boxel-font-size-xs);
          font-variant-numeric: tabular-nums;
          font-weight: 600;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>{{@model.title}}
        <span class='atom-tgt'>{{@model.targetSummary}}</span></span>
      <style scoped>
        .atom {
          display: inline-flex;
          gap: 0.3rem;
          align-items: baseline;
          font-size: 0.8125rem;
          font-weight: 500;
        }
        .atom-tgt {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <article class='fit'>
        <header class='r-head'>
          <ShieldCheckIcon class='fit-glyph' role='presentation' />
          <h3 class='title'>{{@model.title}}</h3>
          <span class='badge'>{{@model.targetSummary}}</span>
        </header>
        {{! Every slot here used to be filled with whatever computed was handy,
            so measured against a real instance 14 of the 16 sizes printed two
            values twice: targetSummary in both the badge and the footer, and
            conditionSummary in both .line and .blurb. Each slot now carries a
            DISTINCT value — condition, prose, breach actions, hours — so no
            quantum repeats itself. }}
        <div class='r-body'>
          <span class='line'>{{@model.conditionSummary}}</span>
          <p class='blurb'>{{@model.cardInfo.summary}}</p>
          <span class='tail'>{{@model.breachActionSummary}}</span>
        </div>
        <footer class='r-meta'>{{@model.businessHoursSummary}}</footer>
      </article>
      <style scoped>
        /* Same skeleton as ticket.gts: one `.fit` grid, no container declared
           here (the host provides `fitted-card`), one continuous type scale,
           and tiers that ADD a row rather than un-crop one. */
        .fit {
          width: 100%;
          height: 100%;
          display: grid;
          grid-template-rows: auto minmax(0, 1fr) auto;
          grid-template-areas: 'head' 'body' 'meta';
          gap: 0.125rem;
          padding: 0.4375rem 0.5625rem;
          overflow: hidden;
          background-color: var(--card);
          color: var(--card-foreground);
          --type-base: clamp(0.5938rem, 2.7cqi, 0.75rem);
          --type-title: max(0.6875rem, calc(var(--type-base) * 1.25));
        }
        .fit > * {
          overflow: hidden;
          min-height: 0;
        }
        .r-head {
          grid-area: head;
          display: flex;
          align-items: baseline;
          gap: 0.3125rem;
          min-width: 0;
        }
        /* fitted-card Rule 2: the anchor. Without it these cells were a title at
           weight 600 plus a badge — no image, no glyph, and 600 is not the
           "decisively loud" type the rule accepts as a substitute, so all 16
           sizes read as bare text. This is the card's OWN icon, the same one its
           isolated section headers use, which is what makes it identity rather
           than decoration.

           Sized in em with a px floor so it never shrinks to a dot; `align-self`
           because the head is a baseline row and an SVG has no baseline; muted so
           the title stays the loudest thing in the cell. */
        .fit-glyph {
          flex: none;
          align-self: center;
          width: max(0.6875rem, 1.1em);
          height: max(0.6875rem, 1.1em);
          color: var(--muted-foreground);
        }
        .title {
          flex: 1;
          min-width: 0;
          margin: 0;
          font-size: var(--type-title);
          font-weight: 600;
          line-height: 1.25;
          letter-spacing: -0.01em;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .badge {
          flex: none;
          margin-left: auto;
          font-family: var(--font-mono);
          font-size: var(--type-base);
          font-weight: 600;
          color: var(--muted-foreground);
          font-variant-numeric: tabular-nums;
          white-space: nowrap;
        }
        .r-body {
          grid-area: body;
          display: none;
          flex-direction: column;
          gap: 0.125rem;
          min-width: 0;
        }
        .line {
          font-size: var(--type-base);
          color: var(--muted-foreground);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .blurb {
          display: none;
          margin: 0;
          font-size: var(--type-base);
          color: var(--muted-foreground);
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .tail {
          display: none;
          margin-top: auto;
          font-size: var(--type-base);
          color: var(--muted-foreground);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .r-meta {
          grid-area: meta;
          display: none;
          align-items: center;
          gap: 0.375rem;
          min-width: 0;
          font-size: var(--type-base);
          color: var(--muted-foreground);
        }
        @container fitted-card (height <= 50px) {
          .fit {
            grid-template-rows: 1fr;
            align-content: center;
          }
          .title {
            -webkit-line-clamp: 1;
          }
        }
        @container fitted-card (height > 50px) {
          .r-meta {
            display: flex;
          }
        }
        @container fitted-card (height > 50px) and (height <= 105px) {
          .title {
            -webkit-line-clamp: 1;
          }
        }
        @container fitted-card (height > 80px) {
          .r-body {
            display: flex;
          }
        }
        @container fitted-card (height > 160px) {
          .blurb {
            display: -webkit-box;
          }
        }
        @container fitted-card (height > 240px) {
          .blurb {
            -webkit-line-clamp: 4;
          }
          .tail {
            display: block;
          }
        }
        @container fitted-card (width > 300px) and (height <= 130px) {
          .fit {
            grid-template-columns: minmax(12.5rem, 1fr) auto;
            grid-template-areas: 'head meta' 'body meta';
            align-items: center;
          }
          .r-meta {
            flex-direction: column;
            align-items: flex-end;
            gap: 1px;
          }
        }
        @container fitted-card (width <= 170px) {
          .fit-glyph {
            display: none;
          }
          /* The glyph is dropped just above, so from here down the anchor is
             type alone — and fitted-card Rule 2's typographic path wants real
             weight. Weight only, never size: at 150px the title is one word from
             wrapping and Rule 1 (nothing clipped) outranks Rule 2. */
          .title {
            font-weight: 700;
          }
        }
      </style>
    </template>
  };
}
