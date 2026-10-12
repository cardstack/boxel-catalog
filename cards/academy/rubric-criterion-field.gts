import {
  Component,
  FieldDef,
  StringField,
  contains,
  containsMany,
  field,
} from '@cardstack/base/card-api';
import MarkdownField from '@cardstack/base/markdown';
import NumberField from '@cardstack/base/number';
import ListCheckIcon from '@cardstack/boxel-icons/list-check';

/** One achievement level of a criterion: a label, the points it earns, and what it looks like. */
export class RubricLevelField extends FieldDef {
  static displayName = 'Rubric Level';
  @field label = contains(StringField);
  @field points = contains(NumberField);
  @field descriptor = contains(StringField, {
    description: 'What work at this level looks like, in one or two sentences.',
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='lvl'><b>{{@model.label}}</b>
        <span class='pts'>{{@model.points}} pts</span></span>
      <style scoped>
        .lvl {
          display: inline-flex;
          gap: var(--boxel-sp-4xs);
          align-items: baseline;
          font-size: var(--boxel-font-size-sm);
        }
        .pts {
          color: var(--muted-foreground, var(--boxel-450));
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };
}

/**
 * One row of a rubric: what is being judged, how much it counts, and the
 * ladder of levels a grader picks from. Points are per level; `weight`
 * multiplies them so a rubric can say "Analysis counts double" without
 * re-pricing every level. `maxPoints` is computed so a rubric edit re-totals.
 *
 * Sibling, not duplicate: `scorecard-field.gts` is the interview scorecard
 * (a 1–5 star per criterion plus a hire recommendation). A rubric has named
 * levels with descriptors and weights — a different data model, so this is
 * its own block rather than a Scorecard variant.
 */
export class RubricCriterionField extends FieldDef {
  static displayName = 'Rubric Criterion';
  static icon = ListCheckIcon;

  @field name = contains(StringField);
  @field description = contains(MarkdownField);
  @field weight = contains(NumberField, {
    description: 'Multiplier on level points. 1 = counts once.',
  });
  @field levels = containsMany(RubricLevelField);

  @field maxPoints = contains(NumberField, {
    computeVia: function (this: RubricCriterionField): number {
      return criterionMaxPoints(this);
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='crit'>
        <div class='crit-head'>
          <span class='crit-name'>{{@model.name}}</span>
          <span class='crit-max'>{{@model.maxPoints}}
            pts{{#if (isWeighted @model.weight)}}
              · ×{{@model.weight}}{{/if}}</span>
        </div>
        <ol class='levels'>
          {{#each (sortedLevels @model) as |lvl|}}
            <li>
              <span class='lvl-label'>{{lvl.label}}</span>
              <span class='lvl-pts'>{{lvl.points}}</span>
              {{#if lvl.descriptor}}
                <span class='lvl-desc'>{{lvl.descriptor}}</span>
              {{/if}}
            </li>
          {{/each}}
        </ol>
      </div>
      <style scoped>
        .crit {
          display: grid;
          gap: var(--boxel-sp-xs);
        }
        .crit-head {
          display: flex;
          justify-content: space-between;
          align-items: baseline;
          gap: var(--boxel-sp-sm);
        }
        .crit-name {
          font-weight: 600;
          color: var(--foreground, var(--boxel-dark));
        }
        .crit-max {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
          font-variant-numeric: tabular-nums;
          white-space: nowrap;
        }
        .levels {
          list-style: none;
          margin: 0;
          padding: 0;
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(9rem, 1fr));
          gap: var(--boxel-sp-4xs);
        }
        .levels li {
          display: grid;
          grid-template-columns: 1fr auto;
          gap: 0 var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs);
          border-radius: var(--radius, var(--boxel-border-radius-sm));
          background: var(--muted, var(--boxel-100));
          font-size: var(--boxel-font-size-sm);
        }
        .lvl-label {
          font-weight: 600;
        }
        .lvl-pts {
          font-variant-numeric: tabular-nums;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .lvl-desc {
          grid-column: 1 / -1;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='crit-atom'>{{@model.name}}
        <span class='crit-atom-max'>{{@model.maxPoints}} pts</span></span>
      <style scoped>
        .crit-atom {
          font-size: var(--boxel-font-size-sm);
          white-space: nowrap;
        }
        .crit-atom-max {
          color: var(--muted-foreground, var(--boxel-450));
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };
}

export function sortedLevels(
  c: Partial<RubricCriterionField> | null | undefined,
): { label: string; points: number; descriptor?: string }[] {
  return (c?.levels ?? [])
    .filter((l: any) => l?.label)
    .map((l: any) => ({
      label: l.label,
      points: l.points ?? 0,
      descriptor: l.descriptor,
    }))
    .sort((a, b) => b.points - a.points);
}

export function criterionMaxPoints(
  c: Partial<RubricCriterionField> | null | undefined,
): number {
  let top = Math.max(0, ...(c?.levels ?? []).map((l: any) => l?.points ?? 0));
  return round1(top * (c?.weight ?? 1));
}

export function isWeighted(w?: number | null): boolean {
  return w != null && w !== 1;
}

export function round1(n: number): number {
  return Math.round(n * 10) / 10;
}

export default RubricCriterionField;
