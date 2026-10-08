import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import TextAreaField from '@cardstack/base/text-area';
import { FieldContainer } from '@cardstack/boxel-ui/components';

import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { SectionedEdit } from '@cardstack/catalog/components/sectioned-edit';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';
import { COMPACT_EMPTY_STYLE } from '@cardstack/catalog/components/pretui-helpers';

function krProgress(kr: KeyResultField | undefined): number {
  if (!kr) {
    return 0;
  }
  let start = kr.startValue ?? 0;
  let target = kr.targetValue ?? 0;
  let current = kr.currentValue ?? start;
  if (target === start) {
    return current >= target ? 100 : 0;
  }
  let pct = ((current - start) / (target - start)) * 100;
  return Math.max(0, Math.min(100, Math.round(pct)));
}

function bandHue(pct: number): 'red' | 'amber' | 'green' {
  if (pct < 40) {
    return 'red';
  }
  if (pct < 70) {
    return 'amber';
  }
  return 'green';
}

// One measurable key result: where it started, where it must land, where it
// is now. Progress is always derived from the three numbers — never stored,
// never hand-set — so a KR cannot claim more than its metric shows.
// The bar's fill per progress band, matching the percentage's ink.
const BAR_HUE: Record<string, string> = {
  red: 'var(--destructive-ink)',
  amber: 'var(--attention-ink)',
  green: 'var(--success-ink)',
};

export class KeyResultField extends FieldDef {
  static displayName = 'Key Result';

  @field description = contains(StringField);
  @field startValue = contains(NumberField);
  @field targetValue = contains(NumberField);
  @field currentValue = contains(NumberField);
  @field unit = contains(StringField, {
    description: 'e.g. %, users, $k, NPS points',
  });

  @field progressPercent = contains(NumberField, {
    computeVia: function (this: KeyResultField) {
      return krProgress(this);
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get pct() {
      return this.args.model?.progressPercent ?? 0;
    }
    get hue() {
      return bandHue(this.pct);
    }
    get barHue() {
      return BAR_HUE[this.hue];
    }
    <template>
      <div class='kr'>
        <div class='kr-top'>
          <span class='kr-desc'>{{@model.description}}</span>
          <span class='kr-nums'>{{@model.currentValue}}
            /
            {{@model.targetValue}}
            {{@model.unit}}</span>
          <span class='kr-pct pct-{{this.hue}}'>{{this.pct}}%</span>
        </div>
        <ProgressBar
          @value={{this.pct}}
          @hue={{this.barHue}}
          aria-label={{@model.description}}
        />
      </div>
      <style scoped>
        .kr {
          display: grid;
          gap: var(--boxel-sp-5xs);
          padding: var(--boxel-sp-4xs) 0;
        }
        .kr-top {
          display: grid;
          grid-template-columns: 1fr auto auto;
          gap: var(--boxel-sp-sm);
          align-items: baseline;
          font-size: 0.875rem;
        }
        .kr-desc {
          font-weight: 600;
        }
        .kr-nums {
          color: var(--muted-foreground);
          font-variant-numeric: tabular-nums;
          font-size: 0.8125rem;
        }
        .kr-pct {
          font-weight: 700;
          font-variant-numeric: tabular-nums;
        }
        .pct-red {
          color: var(--destructive-ink);
        }
        .pct-amber {
          color: var(--attention-ink);
        }
        .pct-green {
          color: var(--success-ink);
        }
      </style>
    </template>
  };
}

// An Objective with its measurable Key Results for one period. Overall
// progress is the mean of the KRs' derived progress — computed, never
// stored. The ambition norm (0.7 is success for aspirational OKRs) is a
// reading convention documented here, not a threshold the card enforces.
export class Okr extends CardDef {
  static displayName = 'OKR';
  static headerColor = '#2f4f4f';

  @field objective = contains(StringField);
  @field period = contains(StringField, {
    description: 'e.g. FY2026 Q3',
  });
  @field owner = linksTo(() => Employee);
  @field keyResults = containsMany(KeyResultField);
  @field notes = contains(TextAreaField);

  @field overallProgress = contains(NumberField, {
    computeVia: function (this: Okr) {
      let krs = (this.keyResults ?? []).filter(Boolean);
      if (!krs.length) {
        return 0;
      }
      let sum = krs.reduce((acc, kr) => acc + krProgress(kr), 0);
      return Math.round(sum / krs.length);
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Okr) {
      return this.objective?.trim()?.length ? this.objective : 'Untitled OKR';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get pct() {
      return this.args.model?.overallProgress ?? 0;
    }
    get hue() {
      return bandHue(this.pct);
    }
    <template>
      <article class='okr'>
        <header class='head'>
          <div>
            <p class='kicker'>Objective · {{@model.period}}</p>
            <h1>{{@model.objective}}</h1>
            {{#if @model.owner}}
              <p class='sub'>owned by <@fields.owner @format='atom' /></p>
            {{/if}}
          </div>
          <div class='score'>
            <span class='score-num pct-{{this.hue}}'>{{this.pct}}%</span>
            <span class='score-label'>overall</span>
          </div>
        </header>
        <section class='panel'>
          <h2>Key Results</h2>
          <div class='krs'>
            {{#each @fields.keyResults as |KR|}}
              <KR />
            {{else}}
              <EmptyState
                @title='No key results yet'
                @message='An objective without measures is a wish.'
                @texture={{false}}
                style={{COMPACT_EMPTY_STYLE}}
              />
            {{/each}}
          </div>
        </section>
        {{#if @model.notes}}
          <section class='panel'>
            <h2>Notes</h2>
            <p class='notes'>{{@model.notes}}</p>
          </section>
        {{/if}}
      </article>
      <style scoped>
        .okr {
          container-type: inline-size;
          padding: var(--boxel-sp-lg);
          background: var(--background);
          color: var(--foreground);
          font-family: var(--font-sans);
          display: grid;
          gap: var(--boxel-sp);
        }
        .head {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          gap: var(--boxel-sp);
          border-bottom: 1px solid var(--border);
          padding-bottom: var(--boxel-sp);
        }
        .kicker {
          margin: 0;
          font-size: 0.6875rem;
          letter-spacing: 0.12em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        h1 {
          margin: var(--boxel-sp-5xs) 0;
          font-size: 1.5rem;
          line-height: 1.25;
        }
        .sub {
          margin: 0;
          color: var(--muted-foreground);
        }
        .score {
          text-align: right;
        }
        .score-num {
          display: block;
          font-size: 2rem;
          font-weight: 700;
          font-variant-numeric: tabular-nums;
        }
        .score-label {
          font-size: 0.6875rem;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: var(--muted-foreground);
        }
        .pct-red {
          color: var(--destructive-ink);
        }
        .pct-amber {
          color: var(--attention-ink);
        }
        .pct-green {
          color: var(--success-ink);
        }
        .panel {
          border: 1px solid var(--border);
          border-radius: var(--radius);
          padding: var(--boxel-sp);
          background: var(--card);
        }
        h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: 0.8125rem;
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .krs {
          display: grid;
          gap: var(--boxel-sp-xs);
        }
        .notes {
          margin: 0;
          white-space: pre-wrap;
          font-size: 0.875rem;
        }
        @container (max-width: 480px) {
          .head {
            flex-direction: column;
          }
          .score {
            text-align: left;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get pct() {
      return this.args.model?.overallProgress ?? 0;
    }
    get hue() {
      return bandHue(this.pct);
    }
    get krCount() {
      return (this.args.model?.keyResults ?? []).length;
    }
    <template>
      <div class='row'>
        <div class='who'>
          <span class='name'>{{@model.objective}}</span>
          <span class='meta'>{{@model.period}} · {{this.krCount}} KRs</span>
        </div>
        <StatePill @label='{{this.pct}}%' @hue={{this.hue}} @dot={{true}} />
      </div>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: 1fr auto;
          gap: var(--boxel-sp-sm);
          align-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .who {
          display: flex;
          flex-direction: column;
          gap: 2px;
          min-width: 0;
        }
        .name {
          font-weight: 600;
          font-size: 0.9375rem;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .meta {
          font-size: 0.8125rem;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>{{@model.objective}}
        ·
        {{@model.overallProgress}}%</span>
      <style scoped>
        .atom {
          font-size: 0.8125rem;
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get pct() {
      return this.args.model?.overallProgress ?? 0;
    }
    get hue() {
      return bandHue(this.pct);
    }
    <template>
      <div class='fit'>
        <span class='fit-name'>{{@model.objective}}</span>
        <span class='fit-sub'>{{@model.period}}</span>
        <span class='fit-pct pct-{{this.hue}}'>{{this.pct}}%</span>
      </div>
      <style scoped>
        .fit {
          height: 100%;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-5xs);
          padding: var(--boxel-sp-xs);
          overflow: hidden;
        }
        .fit-name {
          font-weight: 600;
          font-size: 0.9375rem;
          line-height: 1.2;
          overflow: hidden;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
        }
        .fit-sub {
          font-size: 0.75rem;
          color: var(--muted-foreground);
        }
        .fit-pct {
          margin-top: auto;
          font-size: 1.125rem;
          font-weight: 700;
          font-variant-numeric: tabular-nums;
        }
        .pct-red {
          color: var(--destructive-ink);
        }
        .pct-amber {
          color: var(--attention-ink);
        }
        .pct-green {
          color: var(--success-ink);
        }
        @container fitted-card (height <= 65px) {
          .fit {
            flex-direction: row;
            align-items: center;
            gap: var(--boxel-sp-xs);
          }
          .fit-sub {
            display: none;
          }
          .fit-pct {
            margin-top: 0;
            margin-left: auto;
            font-size: 0.9375rem;
          }
          .fit-name {
            -webkit-line-clamp: 1;
          }
        }
      </style>
    </template>
  };

  // The form for writing an OKR, grouped the way an OKR is authored: state
  // the objective, attach measurable key results, then note anything else.
  // The progress numbers (progressPercent, overallProgress) are DERIVED from
  // the KRs' start/target/current — they are computed fields and never appear
  // here. A left anchor rail (EditSectionNav) tracks the three sections.
  static edit = class Edit extends Component<typeof this> {
    sections = [
      { id: 'objective', label: 'Objective' },
      { id: 'key-results', label: 'Key Results' },
      { id: 'notes', label: 'Notes' },
    ];

    <template>
      <SectionedEdit
        @sections={{this.sections}}
        @ariaLabel='OKR sections'
        as |e|
      >
        <e.Section @id='objective' @title='Objective'>
          <FieldContainer @label='Objective' @vertical={{true}}>
            <@fields.objective />
          </FieldContainer>
          <div class='row'>
            <FieldContainer @label='Period (e.g. FY2026 Q3)' @vertical={{true}}>
              <@fields.period />
            </FieldContainer>
            <FieldContainer @label='Owner' @vertical={{true}}>
              <@fields.owner />
            </FieldContainer>
          </div>
        </e.Section>
        <e.Section
          @id='key-results'
          @title='Key Results'
          @hint='progress is derived from start / target / current — never typed in'
        >
          <FieldContainer
            @label='Key results (description, start, target, current, unit)'
            @vertical={{true}}
          >
            <@fields.keyResults />
          </FieldContainer>
        </e.Section>
        <e.Section @id='notes' @title='Notes'>
          <FieldContainer @label='Notes' @vertical={{true}}>
            <@fields.notes />
          </FieldContainer>
        </e.Section>
      </SectionedEdit>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: repeat(2, minmax(0, 1fr));
          gap: var(--boxel-sp-sm);
          align-items: start;
        }
        @container (width < 40rem) {
          .row,
          .row[class*='cols-'] {
            grid-template-columns: 1fr;
          }
        }
      </style>
    </template>
  };
}
