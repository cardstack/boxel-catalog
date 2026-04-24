import { concat } from '@ember/helper';
// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
} from 'https://cardstack.com/base/card-api'; // ¹ Core imports
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import BooleanField from 'https://cardstack.com/base/boolean';
import DateField from 'https://cardstack.com/base/date';
import {
  formatNumber,
  formatDateTime,
  multiply,
  divide,
  gt,
  or,
  subtract,
} from '@cardstack/boxel-ui/helpers'; // ² Formatters
import { Button, FieldContainer } from '@cardstack/boxel-ui/components'; // ³ UI components
import { tracked } from '@glimmer/tracking'; // ⁴ State

// ⁵ FieldDefs for embedded data
export class MacroBreakdownField extends FieldDef {
  static displayName = 'Macro Breakdown';
  @field protein = contains(NumberField); // grams
  @field carbs = contains(NumberField); // grams
  @field fat = contains(NumberField); // grams

  static embedded = class Embedded extends Component<typeof this> {
    get totals() {
      const p = this.args?.model?.protein ?? 0;
      const c = this.args?.model?.carbs ?? 0;
      const f = this.args?.model?.fat ?? 0;
      const kcal = p * 4 + c * 4 + f * 9;
      return { p, c, f, kcal };
    }
    <template>
      <div class='macros'>
        <div class='rings'>
          <!-- simple concentric rings via CSS; numbers shown plainly -->
          <div class='ring'>
            <span class='label'>Protein</span>
            <span class='value'>{{formatNumber this.totals.p}}</span><span
              class='unit'
            >g</span>
          </div>
          <div class='ring'>
            <span class='label'>Carbs</span>
            <span class='value'>{{formatNumber this.totals.c}}</span><span
              class='unit'
            >g</span>
          </div>
          <div class='ring'>
            <span class='label'>Fat</span>
            <span class='value'>{{formatNumber this.totals.f}}</span><span
              class='unit'
            >g</span>
          </div>
        </div>
        <div class='kcal'>
          <span class='kval'>{{formatNumber this.totals.kcal}}</span>
          <span class='kunit'>kcal</span>
        </div>
      </div>
      <style scoped>
        .macros {
          --bg: oklch(0.14 0.02 270);
          --ink: oklch(0.92 0.03 270);
          --grid: oklch(0.28 0.06 270);
          --magenta: oklch(0.68 0.25 330);
          --cyan: oklch(0.76 0.14 210);
          --glow: 0 0 0.25rem
            color-mix(in oklch, var(--magenta) 70%, var(--cyan) 30%);
          display: grid;
          grid-template-columns: 1fr auto;
          gap: 0.75rem;
          align-items: start;
          color: var(--ink);
        }
        .rings {
          display: grid;
          grid-template-columns: repeat(3, minmax(0, 1fr));
          gap: 0.5rem;
        }
        .ring {
          padding: 0.5rem;
          border: 1px solid var(--grid);
          border-radius: 10px;
          background: linear-gradient(
            180deg,
            color-mix(in oklch, var(--bg) 85%, black 15%),
            var(--bg)
          );
          box-shadow:
            inset 0 0 0.5rem color-mix(in oklch, var(--cyan) 30%, transparent),
            0 0 0 var(--_border, 0px) var(--magenta);
        }
        .label {
          display: block;
          font-size: 0.75rem;
          color: var(--ink);
          opacity: 0.8;
          letter-spacing: 0.02em;
        }
        .value {
          font-weight: 700;
          color: var(--ink);
          text-shadow: 0 0 0.25rem
            color-mix(in oklch, var(--cyan) 35%, transparent);
        }
        .unit {
          margin-left: 0.125rem;
          opacity: 0.85;
        }
        .kcal {
          display: flex;
          flex-direction: column;
          align-items: flex-end;
          gap: 0.125rem;
        }
        .kval {
          font-size: 1rem;
          font-weight: 800;
          color: var(--ink);
        }
        .kunit {
          font-size: 0.75rem;
          opacity: 0.8;
        }
        @media (prefers-reduced-motion: no-preference) {
          .ring {
            --_border: 0px;
            transition:
              box-shadow 180ms ease,
              border-color 180ms ease;
          }
          .ring:hover {
            border-color: var(--magenta);
            box-shadow: var(--glow);
          }
        }
      </style>
    </template>
  };
}

export class MealEntryField extends FieldDef {
  static displayName = 'Meal Entry';
  @field name = contains(StringField);
  @field calories = contains(NumberField);
  @field protein = contains(NumberField);
  @field carbs = contains(NumberField);
  @field fat = contains(NumberField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='meal'>
        <div class='left'>
          <div class='title'>{{if @model.name @model.name 'Meal'}}</div>
          <div class='sub'>
            {{formatNumber @model.protein}}g P •
            {{formatNumber @model.carbs}}g C •
            {{formatNumber @model.fat}}g F
          </div>
        </div>
        <div class='right'>
          <span class='kcal'>{{formatNumber @model.calories}}</span><span
            class='unit'
          >kcal</span>
        </div>
      </div>
      <style scoped>
        .meal {
          --bg: oklch(0.15 0.02 270);
          --grid: oklch(0.32 0.07 270);
          --magenta: oklch(0.68 0.25 330);
          --cyan: oklch(0.76 0.14 210);
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding: 0.5rem 0.625rem;
          border: 1px solid var(--grid);
          border-radius: 10px;
          background: linear-gradient(
            180deg,
            var(--bg),
            color-mix(in oklch, var(--bg) 85%, black 15%)
          );
        }
        .title {
          font-weight: 700;
          letter-spacing: 0.01em;
        }
        .sub {
          font-size: 0.75rem;
          opacity: 0.85;
        }
        .right .kcal {
          font-weight: 800;
          color: oklch(0.94 0.03 270);
          text-shadow: 0 0 0.25rem
            color-mix(in oklch, var(--magenta) 50%, transparent);
        }
        .unit {
          margin-left: 0.125rem;
          opacity: 0.8;
        }
      </style>
    </template>
  };
}

export class DaySummaryField extends FieldDef {
  static displayName = 'Day Summary';
  @field date = contains(DateField);
  @field totalCalories = contains(NumberField);
  @field goalCalories = contains(NumberField);
  @field macros = contains(MacroBreakdownField);
  @field meals = containsMany(MealEntryField);

  static embedded = class Embedded extends Component<typeof this> {
    get remaining() {
      const total = this.args?.model?.totalCalories ?? 0;
      const goal = this.args?.model?.goalCalories ?? 0;
      return goal - total;
    }
    <template>
      <div class='day-summary'>
        <header class='header'>
          <div class='date'>{{if
              @model.date
              (formatDateTime @model.date size='short')
              'Today'
            }}</div>
          <div class='goal'>
            <span class='total'>{{formatNumber
                @model.totalCalories
              }}</span>/<span class='goalv'>{{formatNumber
                @model.goalCalories
              }}</span>
            kcal
          </div>
        </header>
        <div class='bar'>
          <div
            class='fill'
            style={{concat
              'width: '
              (formatNumber
                (multiply
                  (divide
                    @model.totalCalories
                    (if @model.goalCalories @model.goalCalories 1)
                  )
                  100
                )
              )
              '%'
            }}
          ></div>
        </div>
        <section class='macros'>
          <@fields.macros />
        </section>
        {{#if (gt @model.meals.length 0)}}
          <section class='meals'>
            <div class='list'><@fields.meals @format='embedded' /></div>
          </section>
        {{else}}
          <section class='empty'>No meals yet. Try Quick Add.</section>
        {{/if}}
      </div>
      <style scoped>
        .day-summary {
          --bg: oklch(0.12 0.02 270);
          --ink: oklch(0.95 0.03 270);
          --grid: oklch(0.32 0.07 270);
          --magenta: oklch(0.68 0.25 330);
          --cyan: oklch(0.76 0.14 210);
          display: grid;
          gap: 0.75rem;
          color: var(--ink);
        }
        .header {
          display: flex;
          justify-content: space-between;
          align-items: baseline;
        }
        .date {
          font-weight: 800;
          letter-spacing: 0.01em;
        }
        .goal .total {
          font-weight: 800;
          color: var(--ink);
          text-shadow: 0 0 0.2rem
            color-mix(in oklch, var(--cyan) 40%, transparent);
        }
        .bar {
          height: 10px;
          background: linear-gradient(
            180deg,
            color-mix(in oklch, var(--bg) 80%, black 20%),
            var(--bg)
          );
          border-radius: 9999px;
          overflow: hidden;
          border: 1px solid var(--grid);
        }
        .fill {
          height: 100%;
          background: linear-gradient(90deg, var(--magenta), var(--cyan));
        }
        .meals .list > .containsMany-field {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }
        .empty {
          font-size: 0.8125rem;
          opacity: 0.8;
        }
      </style>
    </template>
  };
}

// ⁶ Main CardDef
export class CalorieCounter extends CardDef {
  static displayName = 'Calorie Counter';
  static prefersWideFormat = true;

  @field goalCalories = contains(NumberField);
  @field today = contains(DaySummaryField);

  // ⁷ Safe computed title from goal/today
  @field title = contains(StringField, {
    computeVia: function (this: CalorieCounter) {
      try {
        const goal = this.goalCalories ?? this.today?.goalCalories ?? 0;
        const total = this.today?.totalCalories ?? 0;
        if (!goal && !total) return 'Calorie Counter';
        return `Calorie Counter – ${total}/${goal} kcal`;
      } catch (e) {
        return 'Calorie Counter';
      }
    },
  });

  // ⁸ Embedded format (dashboard card)
  static embedded = class Embedded extends Component<typeof CalorieCounter> {
    <template>
      <div class='ccard'>
        <header class='head'>
          <h4 class='title'>{{if
              @model.title
              @model.title
              'Calorie Counter'
            }}</h4>
          <Button class='add-btn'>Add Meal</Button>
        </header>
        <section class='summary'>
          {{#if @model.today}}
            <@fields.today />
          {{else}}
            <div class='empty'>No data yet. Set your daily goal and start
              tracking.</div>
          {{/if}}
        </section>
      </div>
      <style scoped>
        .ccard {
          --bg: oklch(0.1 0.02 270);
          --grid: oklch(0.32 0.07 270);
          --ink: oklch(0.95 0.03 270);
          --magenta: oklch(0.68 0.25 330);
          --cyan: oklch(0.76 0.14 210);
          padding: 0.875rem;
          border: 1px solid var(--grid);
          border-radius: 12px;
          background: linear-gradient(
            180deg,
            var(--bg),
            color-mix(in oklch, var(--bg) 85%, black 15%)
          );
          display: grid;
          gap: 0.75rem;
          color: var(--ink);
        }
        .head {
          display: flex;
          justify-content: space-between;
          align-items: center;
        }
        .title {
          font-size: 0.95rem;
          font-weight: 800;
          letter-spacing: 0.01em;
        }
        .add-btn {
          padding: 0.375rem 0.75rem;
          font-size: 0.8125rem;
          border: 1px solid var(--grid);
          border-radius: 9999px;
          color: var(--ink);
          background: linear-gradient(
            90deg,
            color-mix(in oklch, var(--magenta) 35%, transparent),
            color-mix(in oklch, var(--cyan) 25%, transparent)
          );
        }
        .summary .list > .containsMany-field {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }
        .empty {
          font-size: 0.8125rem;
          opacity: 0.85;
        }
      </style>
    </template>
  };

  // ⁹ Fitted format with 4 subformats
  static fitted = class Fitted extends Component<typeof CalorieCounter> {
    <template>
      <div class='fitted'>
        <div class='badge-format'>
          <div class='row'>
            <span class='name'>Calories</span>
            <span class='val'>{{formatNumber @model.today.totalCalories}}
              /
              {{formatNumber
                (or @model.goalCalories @model.today.goalCalories)
              }}</span>
          </div>
        </div>
        <div class='strip-format'>
          <div class='left'>
            <span class='name'>Today</span>
            <span class='sub'>{{formatNumber @model.today.totalCalories}}
              kcal</span>
          </div>
          <div class='right'>
            <div class='bar'><div class='fill'></div></div>
          </div>
        </div>
        <div class='tile-format'>
          <div class='top'>
            <div class='big'>{{formatNumber @model.today.totalCalories}}
              kcal</div>
            <div class='goal'>Goal
              {{formatNumber
                (or @model.goalCalories @model.today.goalCalories)
              }}</div>
          </div>
          <div class='bottom'>
            {{#if @model.today.macros}}<@fields.today
                @format='embedded'
              />{{/if}}
          </div>
        </div>
        <div class='card-format'>
          <div class='a'>
            <div class='big'>{{formatNumber @model.today.totalCalories}}
              kcal</div>
            <div class='sub'>Remaining
              {{formatNumber
                (subtract
                  (or @model.goalCalories @model.today.goalCalories)
                  @model.today.totalCalories
                )
              }}</div>
          </div>
          <div class='b'>
            {{#if @model.today.macros}}<@fields.today
                @format='embedded'
              />{{/if}}
          </div>
        </div>
      </div>
      <style scoped>
        .fitted {
          --bg: oklch(0.1 0.02 270);
          --ink: oklch(0.95 0.03 270);
          --grid: oklch(0.32 0.07 270);
          --magenta: oklch(0.68 0.25 330);
          --cyan: oklch(0.76 0.14 210);
          container-type: size;
          width: 100%;
          height: 100%;
          padding: clamp(0.1875rem, 2%, 0.625rem);
          box-sizing: border-box;
          color: var(--ink);
        }
        .badge-format,
        .strip-format,
        .tile-format,
        .card-format {
          display: none;
          width: 100%;
          height: 100%;
          border: 1px solid var(--grid);
          border-radius: 10px;
          background: linear-gradient(
            180deg,
            var(--bg),
            color-mix(in oklch, var(--bg) 85%, black 15%)
          );
          padding: 0.375rem 0.5rem;
          box-sizing: border-box;
        }
        /* Activation ranges */
        @container (max-width: 150px) and (max-height: 169px) {
          .badge-format {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 0.25rem;
          }
        }
        @container (min-width: 151px) and (max-height: 169px) {
          .strip-format {
            display: grid;
            grid-template-columns: 1fr auto;
            align-items: center;
            gap: 0.5rem;
          }
          .strip-format .bar {
            width: clamp(100px, 45%, 160px);
          }
        }
        @container (max-width: 399px) and (min-height: 170px) {
          .tile-format {
            display: grid;
            grid-template-rows: auto 1fr;
            gap: 0.5rem;
          }
        }
        @container (min-width: 400px) and (min-height: 170px) {
          .card-format {
            display: grid;
            grid-template-rows: auto 1fr;
            gap: 0.5rem;
          }
        }

        .name {
          font-weight: 800;
          letter-spacing: 0.01em;
        }
        .val,
        .big {
          font-weight: 900;
          text-shadow: 0 0 0.25rem
            color-mix(in oklch, var(--magenta) 40%, transparent);
        }
        .bar {
          width: 120px;
          height: 8px;
          background: linear-gradient(
            180deg,
            color-mix(in oklch, var(--bg) 80%, black 20%),
            var(--bg)
          );
          border-radius: 9999px;
          overflow: hidden;
          border: 1px solid var(--grid);
        }
        .bar .fill {
          width: 60%;
          height: 100%;
          background: linear-gradient(90deg, var(--magenta), var(--cyan));
        }
        .goal,
        .sub {
          font-size: 0.75rem;
          opacity: 0.85;
        }
      </style>
    </template>
  };

  // ¹⁰ Isolated format (scrollable, quick-add stub)
  static isolated = class Isolated extends Component<typeof CalorieCounter> {
    @tracked showQuickAdd = false;

    <template>
      <div class='stage'>
        <article class='mat'>
          <header class='top'>
            <h1>{{if @model.title @model.title 'Calorie Counter'}}</h1>
            <div class='actions'>
              <Button class='primary'>Add Meal</Button>
              <Button class='ghost'>View Week</Button>
            </div>
          </header>

          {{#if @model.today}}
            <section class='summary'>
              <@fields.today />
            </section>
          {{else}}
            <section class='empty'>Set your goal and start adding meals. Small
              steps win.</section>
          {{/if}}

          <section class='tips'>
            <div class='chip'>Hydration check</div>
            <div class='chip'>Protein pacing</div>
            <div class='chip'>Evening snack swap</div>
          </section>
        </article>
      </div>

      <style scoped>
        .stage {
          --bg: oklch(0.1 0.02 270);
          --grid: oklch(0.32 0.07 270);
          --ink: oklch(0.95 0.03 270);
          --magenta: oklch(0.68 0.25 330);
          --cyan: oklch(0.76 0.14 210);
          width: 100%;
          height: 100%;
          display: flex;
          justify-content: center;
          padding: 0.5rem;
          color: var(--ink);
          background:
            radial-gradient(
              80% 60% at 20% 10%,
              color-mix(in oklch, var(--magenta) 12%, transparent),
              transparent 60%
            ),
            radial-gradient(
              80% 60% at 80% 90%,
              color-mix(in oklch, var(--cyan) 12%, transparent),
              transparent 60%
            ),
            linear-gradient(
              180deg,
              color-mix(in oklch, var(--bg) 85%, black 15%),
              var(--bg)
            );
        }
        .mat {
          max-width: 48rem;
          width: 100%;
          padding: 1.25rem;
          overflow-y: auto;
          max-height: 100%;
          display: grid;
          gap: 1rem;
          border: 1px solid var(--grid);
          border-radius: 14px;
          backdrop-filter: blur(2px);
          background: linear-gradient(
            180deg,
            color-mix(in oklch, var(--bg) 75%, black 25%),
            var(--bg)
          );
        }
        .top {
          display: flex;
          justify-content: space-between;
          align-items: center;
        }
        .top h1 {
          font-size: 1.125rem;
          line-height: 1.2;
          font-weight: 900;
          letter-spacing: 0.01em;
          text-shadow: 0 0 0.25rem
            color-mix(in oklch, var(--magenta) 35%, transparent);
        }
        .actions .primary,
        .actions .ghost {
          padding: 0.5rem 0.75rem;
          font-size: 0.8125rem;
          border: 1px solid var(--grid);
          border-radius: 9999px;
          color: var(--ink);
        }
        .actions .primary {
          background: linear-gradient(90deg, var(--magenta), var(--cyan));
        }
        .actions .ghost {
          background: color-mix(in oklch, var(--bg) 70%, black 30%);
        }
        .summary .list > .containsMany-field {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }
        .tips {
          display: flex;
          gap: 0.5rem;
          flex-wrap: wrap;
        }
        .chip {
          padding: 0.375rem 0.5rem;
          border: 1px solid var(--grid);
          border-radius: 9999px;
          font-size: 0.75rem;
          background: linear-gradient(
            180deg,
            color-mix(in oklch, var(--bg) 80%, black 20%),
            var(--bg)
          );
        }
        .empty {
          font-size: 0.875rem;
          opacity: 0.9;
        }
      </style>
    </template>
  };
}
