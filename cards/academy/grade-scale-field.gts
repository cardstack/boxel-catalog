import {
  Component,
  FieldDef,
  StringField,
  contains,
  containsMany,
  field,
} from '@cardstack/base/card-api';
import PercentageField from '@cardstack/base/percentage';
import AwardIcon from '@cardstack/boxel-icons/award';

/** One band of a grade scale: the letter earned at or above `minPct`. */
export class GradeBandField extends FieldDef {
  static displayName = 'Grade Band';
  @field letter = contains(StringField);
  @field minPct = contains(PercentageField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='band'><b>{{@model.letter}}</b> ≥ {{@model.minPct}}%</span>
      <style scoped>
        .band {
          font-size: var(--boxel-font-size-sm);
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };
}

/**
 * Maps a percentage to a letter. Bands are stored highest-first; the first
 * band whose `minPct` the percentage reaches wins, and a percentage below
 * every band earns the lowest letter. The letter itself is never stored on
 * a Grade — it is recomputed so a scale correction re-letters the cohort.
 */
export class GradeScaleField extends FieldDef {
  static displayName = 'Grade Scale';
  static icon = AwardIcon;

  @field bands = containsMany(GradeBandField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <ol class='scale'>
        {{#each (sortedBands @model) as |band|}}
          <li>
            <span class='letter'>{{band.letter}}</span>
            <span class='min'>≥ {{band.minPct}}%</span>
          </li>
        {{else}}
          <li class='empty'>No bands — default A–F scale applies</li>
        {{/each}}
      </ol>
      <style scoped>
        .scale {
          list-style: none;
          margin: 0;
          padding: 0;
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
        }
        li {
          display: inline-flex;
          align-items: baseline;
          gap: var(--boxel-sp-4xs);
          padding: var(--boxel-sp-5xs) var(--boxel-sp-xs);
          border-radius: var(--radius, var(--boxel-border-radius-sm));
          background: var(--muted, var(--boxel-100));
          font-size: var(--boxel-font-size-sm);
          font-variant-numeric: tabular-nums;
        }
        .letter {
          font-weight: 700;
          color: var(--foreground, var(--boxel-dark));
        }
        .min {
          color: var(--muted-foreground, var(--boxel-450));
        }
        .empty {
          background: none;
          color: var(--muted-foreground, var(--boxel-450));
          font-style: italic;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='scale-atom'>{{scaleSummary @model}}</span>
      <style scoped>
        .scale-atom {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
          white-space: nowrap;
        }
      </style>
    </template>
  };
}

export const DEFAULT_GRADE_BANDS = [
  { letter: 'A', minPct: 90 },
  { letter: 'B', minPct: 80 },
  { letter: 'C', minPct: 70 },
  { letter: 'D', minPct: 60 },
  { letter: 'F', minPct: 0 },
];

export function sortedBands(
  scale: Partial<GradeScaleField> | null | undefined,
): { letter: string; minPct: number }[] {
  let bands = (scale?.bands ?? [])
    .filter((b: any) => b?.letter)
    .map((b: any) => ({ letter: b.letter, minPct: b.minPct ?? 0 }));
  if (!bands.length) bands = [...DEFAULT_GRADE_BANDS];
  return bands.sort((a, b) => b.minPct - a.minPct);
}

/** The letter earned for `pct` under `scale` (defaults to A–F). */
export function letterFor(
  pct: number | null | undefined,
  scale?: Partial<GradeScaleField> | null,
): string | undefined {
  if (pct == null || Number.isNaN(pct)) return undefined;
  let bands = sortedBands(scale);
  for (let b of bands) {
    if (pct >= b.minPct) return b.letter;
  }
  return bands[bands.length - 1]?.letter;
}

/** Whether `letter` meets or beats `minLetter` under `scale`. */
export function letterAtLeast(
  letter: string | undefined,
  minLetter: string | undefined,
  scale?: Partial<GradeScaleField> | null,
): boolean {
  if (!minLetter) return true;
  if (!letter) return false;
  let bands = sortedBands(scale);
  let rank = (l: string) => bands.findIndex((b) => b.letter === l);
  let a = rank(letter);
  let m = rank(minLetter);
  if (a < 0 || m < 0) return false;
  return a <= m;
}

export function scaleSummary(
  scale: Partial<GradeScaleField> | null | undefined,
): string {
  return sortedBands(scale)
    .map((b) => b.letter)
    .join(' / ');
}

export default GradeScaleField;
