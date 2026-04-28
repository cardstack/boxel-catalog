// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
// ¹ Core imports
import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  linksToMany,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import DateField from 'https://cardstack.com/base/date';
import BooleanField from 'https://cardstack.com/base/boolean';
import MarkdownField from 'https://cardstack.com/base/markdown';
import enumField from 'https://cardstack.com/base/enum';
import { tracked } from '@glimmer/tracking';
import { fn, concat } from '@ember/helper';
import { on } from '@ember/modifier';
import {
  eq,
  gt,
  or,
  not,
  subtract,
  add,
  multiply,
  divide,
} from '@cardstack/boxel-ui/helpers';
import { Button } from '@cardstack/boxel-ui/components';
import DumbbellIcon from '@cardstack/boxel-icons/dumbbell';
import TargetIcon from '@cardstack/boxel-icons/target';
import ActivityIcon from '@cardstack/boxel-icons/activity';
import TrendingUpIcon from '@cardstack/boxel-icons/trending-up';
import CheckCircleIcon from '@cardstack/boxel-icons/check-circle';
import FlameIcon from '@cardstack/boxel-icons/flame';

// ² Enum fields
const MuscleGroupField = enumField(StringField, {
  options: [
    'Chest',
    'Back',
    'Shoulders',
    'Arms',
    'Core',
    'Legs',
    'Glutes',
    'Full Body',
    'Cardio',
  ],
});

const DifficultyField = enumField(StringField, {
  options: ['Beginner', 'Intermediate', 'Advanced'],
});

const GoalTypeField = enumField(StringField, {
  options: [
    'Weight Loss',
    'Muscle Gain',
    'Endurance',
    'Flexibility',
    'Strength',
    'General Fitness',
  ],
});

const WorkoutTypeField = enumField(StringField, {
  options: [
    'Strength',
    'Cardio',
    'HIIT',
    'Yoga',
    'Pilates',
    'CrossFit',
    'Swimming',
    'Running',
    'Cycling',
  ],
});

const UnitField = enumField(StringField, {
  options: ['kg', 'lbs', 'reps', 'minutes', 'meters', 'km', 'miles'],
});

// ³ ExerciseSet FieldDef
export class ExerciseSet extends FieldDef {
  static displayName = 'Exercise Set';

  @field setNumber = contains(NumberField);
  @field reps = contains(NumberField);
  @field weight = contains(NumberField);
  @field unit = contains(UnitField);
  @field duration = contains(NumberField); // in seconds
  @field restTime = contains(NumberField); // in seconds
  @field notes = contains(StringField);

  static embedded = class Embedded extends Component<typeof ExerciseSet> {
    <template>
      <div class='set-row'>
        <span class='set-num'>Set
          {{if @model.setNumber @model.setNumber '—'}}</span>
        {{#if @model.reps}}
          <span class='set-stat'>
            <svg
              width='12'
              height='12'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            ><circle cx='12' cy='12' r='10' /><path d='M12 8v4l3 3' /></svg>
            {{@model.reps}}
            reps
          </span>
        {{/if}}
        {{#if @model.weight}}
          <span class='set-stat'>
            <svg
              width='12'
              height='12'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            ><path d='M6 4v16M18 4v16M2 9h20M2 15h20' /></svg>
            {{@model.weight}}
            {{if @model.unit @model.unit 'kg'}}
          </span>
        {{/if}}
        {{#if @model.duration}}
          <span class='set-stat'>
            <svg
              width='12'
              height='12'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            ><circle cx='12' cy='12' r='10' /><polyline
                points='12 6 12 12 16 14'
              /></svg>
            {{@model.duration}}s
          </span>
        {{/if}}
        {{#if @model.notes}}
          <span class='set-note'>{{@model.notes}}</span>
        {{/if}}
      </div>
      <style scoped>
        .set-row {
          display: flex;
          align-items: center;
          gap: 0.625rem;
          padding: 0.375rem 0.5rem;
          border-radius: 0.375rem;
          background: var(--muted);
          font-size: 0.8125rem;
        }
        .set-num {
          font-weight: 600;
          color: var(--primary);
          min-width: 2.5rem;
        }
        .set-stat {
          display: flex;
          align-items: center;
          gap: 0.25rem;
          color: var(--foreground);
        }
        .set-note {
          color: var(--muted-foreground);
          font-style: italic;
          margin-left: auto;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof ExerciseSet> {
    <template>
      <span>{{if @model.reps @model.reps '—'}}
        reps @
        {{if @model.weight @model.weight '—'}}
        {{if @model.unit @model.unit 'kg'}}</span>
    </template>
  };
}

// ⁴ ExerciseLog FieldDef
export class ExerciseLog extends FieldDef {
  static displayName = 'Exercise Log';

  @field exerciseName = contains(StringField);
  @field muscleGroup = contains(MuscleGroupField);
  @field sets = containsMany(ExerciseSet);
  @field totalVolume = contains(NumberField, {
    computeVia: function (this: ExerciseLog) {
      try {
        if (!Array.isArray(this.sets) || !this.sets.length) return 0;
        return this.sets.reduce((sum: number, s: ExerciseSet) => {
          const reps = s?.reps ?? 0;
          const weight = s?.weight ?? 0;
          return sum + reps * weight;
        }, 0);
      } catch (e) {
        return 0;
      }
    },
  });
  @field notes = contains(StringField);

  static embedded = class Embedded extends Component<typeof ExerciseLog> {
    <template>
      <div class='exercise-log'>
        <div class='exercise-header'>
          <span class='exercise-name'>{{if
              @model.exerciseName
              @model.exerciseName
              'Unnamed Exercise'
            }}</span>
          {{#if @model.muscleGroup}}
            <span class='muscle-badge'>{{@model.muscleGroup}}</span>
          {{/if}}
          {{#if @model.totalVolume}}
            <span class='volume-badge'>Vol: {{@model.totalVolume}} kg</span>
          {{/if}}
        </div>
        {{#if @model.sets.length}}
          <div class='sets-list'>
            <@fields.sets @format='embedded' />
          </div>
        {{else}}
          <p class='no-sets'>No sets logged</p>
        {{/if}}
        {{#if @model.notes}}
          <p class='exercise-notes'>{{@model.notes}}</p>
        {{/if}}
      </div>
      <style scoped>
        .exercise-log {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
          padding: 0.75rem;
          background: var(--card);
          border: 1px solid var(--border);
          border-radius: var(--radius);
        }
        .exercise-header {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          flex-wrap: wrap;
        }
        .exercise-name {
          font-weight: 600;
          font-size: 0.9375rem;
          color: var(--card-foreground);
        }
        .muscle-badge {
          font-size: 0.6875rem;
          padding: 0.125rem 0.5rem;
          border-radius: 9999px;
          background: var(--primary);
          color: var(--primary-foreground);
          font-weight: 500;
        }
        .volume-badge {
          font-size: 0.6875rem;
          padding: 0.125rem 0.5rem;
          border-radius: 9999px;
          background: var(--accent);
          color: var(--accent-foreground);
          margin-left: auto;
        }
        .sets-list > .containsMany-field {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
        }
        .no-sets,
        .exercise-notes {
          font-size: 0.8125rem;
          color: var(--muted-foreground);
          margin: 0;
          font-style: italic;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof ExerciseLog> {
    <template>
      <span>{{if @model.exerciseName @model.exerciseName 'Exercise'}}
        ({{if @model.sets.length @model.sets.length 0}}
        sets)</span>
    </template>
  };
}

// ⁵ FitnessGoal CardDef
export class FitnessGoal extends CardDef {
  static displayName = 'Fitness Goal';
  static icon = TargetIcon;
  static prefersWideFormat = false;

  @field goalType = contains(GoalTypeField);
  @field targetValue = contains(NumberField);
  @field targetUnit = contains(UnitField);
  @field deadline = contains(DateField);
  @field currentValue = contains(NumberField);
  @field description = contains(StringField);
  @field isCompleted = contains(BooleanField);
  @field notes = contains(MarkdownField);

  @field progressPercent = contains(NumberField, {
    computeVia: function (this: FitnessGoal) {
      try {
        const current = this.currentValue ?? 0;
        const target = this.targetValue ?? 1;
        return Math.min(100, Math.round((current / target) * 100));
      } catch {
        return 0;
      }
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: FitnessGoal) {
      return this.cardInfo?.name ?? this.goalType ?? 'Fitness Goal';
    },
  });

  static embedded = class Embedded extends Component<typeof FitnessGoal> {
    <template>
      <div class='goal-card'>
        <div class='goal-top'>
          <div class='goal-icon'>
            <svg
              width='18'
              height='18'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            ><circle cx='12' cy='12' r='10' /><circle
                cx='12'
                cy='12'
                r='6'
              /><circle cx='12' cy='12' r='2' /></svg>
          </div>
          <div class='goal-info'>
            <span class='goal-type'>{{if
                @model.goalType
                @model.goalType
                'Goal'
              }}</span>
            {{#if @model.description}}
              <span class='goal-desc'>{{@model.description}}</span>
            {{/if}}
          </div>
          {{#if @model.isCompleted}}
            <span class='completed-badge'>✓ Done</span>
          {{/if}}
        </div>
        <div class='goal-progress'>
          <div class='progress-bar-bg'>
            <div
              class='progress-bar-fill'
              style={{concat 'width:' @model.progressPercent '%'}}
            ></div>
          </div>
          <div class='progress-labels'>
            <span>{{if @model.currentValue @model.currentValue 0}}
              /
              {{if @model.targetValue @model.targetValue '?'}}
              {{if @model.targetUnit @model.targetUnit ''}}</span>
            <span class='progress-pct'>{{if
                @model.progressPercent
                @model.progressPercent
                0
              }}%</span>
          </div>
        </div>
        {{#if @model.deadline}}
          <div class='goal-deadline'>
            <svg
              width='12'
              height='12'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            ><rect x='3' y='4' width='18' height='18' rx='2' ry='2' /><line
                x1='16'
                y1='2'
                x2='16'
                y2='6'
              /><line x1='8' y1='2' x2='8' y2='6' /><line
                x1='3'
                y1='10'
                x2='21'
                y2='10'
              /></svg>
            Deadline:
            <@fields.deadline />
          </div>
        {{/if}}
      </div>
      <style scoped>
        .goal-card {
          display: flex;
          flex-direction: column;
          gap: 0.625rem;
          padding: 0.875rem;
          background: var(--card);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          box-shadow: var(--shadow-sm);
        }
        .goal-top {
          display: flex;
          align-items: flex-start;
          gap: 0.625rem;
        }
        .goal-icon {
          width: 2rem;
          height: 2rem;
          border-radius: 0.5rem;
          background: var(--primary);
          color: var(--primary-foreground);
          display: flex;
          align-items: center;
          justify-content: center;
          flex-shrink: 0;
        }
        .goal-info {
          flex: 1;
          display: flex;
          flex-direction: column;
          gap: 0.125rem;
        }
        .goal-type {
          font-weight: 600;
          font-size: 0.9375rem;
          color: var(--card-foreground);
        }
        .goal-desc {
          font-size: 0.8125rem;
          color: var(--muted-foreground);
        }
        .completed-badge {
          font-size: 0.6875rem;
          padding: 0.25rem 0.625rem;
          border-radius: 9999px;
          background: #22c55e20;
          color: #22c55e;
          font-weight: 600;
        }
        .goal-progress {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
        }
        .progress-bar-bg {
          height: 0.5rem;
          background: var(--muted);
          border-radius: 9999px;
          overflow: hidden;
        }
        .progress-bar-fill {
          height: 100%;
          background: linear-gradient(90deg, var(--primary), var(--chart-2));
          border-radius: 9999px;
          transition: width 0.4s ease;
        }
        .progress-labels {
          display: flex;
          justify-content: space-between;
          font-size: 0.75rem;
          color: var(--muted-foreground);
        }
        .progress-pct {
          font-weight: 600;
          color: var(--primary);
        }
        .goal-deadline {
          display: flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.75rem;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof FitnessGoal> {
    <template>
      <div class='goal-fitted'>
        <div class='badge'>
          <svg
            width='14'
            height='14'
            viewBox='0 0 24 24'
            fill='none'
            stroke='currentColor'
            stroke-width='2'
          ><circle cx='12' cy='12' r='10' /><circle
              cx='12'
              cy='12'
              r='6'
            /><circle cx='12' cy='12' r='2' /></svg>
          <span>{{if @model.goalType @model.goalType 'Goal'}}</span>
        </div>
        <div class='strip'>
          <div class='strip-left'>
            <svg
              width='16'
              height='16'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            ><circle cx='12' cy='12' r='10' /><circle
                cx='12'
                cy='12'
                r='6'
              /><circle cx='12' cy='12' r='2' /></svg>
            <div class='strip-info'>
              <span class='strip-type'>{{if
                  @model.goalType
                  @model.goalType
                  'Goal'
                }}</span>
              <span class='strip-desc'>{{if
                  @model.description
                  @model.description
                  'No description'
                }}</span>
            </div>
          </div>
          <span class='strip-pct'>{{if
              @model.progressPercent
              @model.progressPercent
              0
            }}%</span>
        </div>
        <div class='tile'>
          <div class='tile-header'>
            <svg
              width='20'
              height='20'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            ><circle cx='12' cy='12' r='10' /><circle
                cx='12'
                cy='12'
                r='6'
              /><circle cx='12' cy='12' r='2' /></svg>
            <span class='tile-type'>{{if
                @model.goalType
                @model.goalType
                'Goal'
              }}</span>
            {{#if @model.isCompleted}}<span class='tile-done'>✓</span>{{/if}}
          </div>
          <div class='tile-progress'>
            <div class='tile-bar-bg'>
              <div
                class='tile-bar-fill'
                style={{concat 'width:' @model.progressPercent '%'}}
              ></div>
            </div>
            <span class='tile-pct'>{{if
                @model.progressPercent
                @model.progressPercent
                0
              }}%</span>
          </div>
          <span class='tile-values'>{{if
              @model.currentValue
              @model.currentValue
              0
            }}
            /
            {{if @model.targetValue @model.targetValue '?'}}
            {{if @model.targetUnit @model.targetUnit ''}}</span>
        </div>
        <div class='card'>
          <div class='card-header'>
            <div class='card-icon'>
              <svg
                width='18'
                height='18'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              ><circle cx='12' cy='12' r='10' /><circle
                  cx='12'
                  cy='12'
                  r='6'
                /><circle cx='12' cy='12' r='2' /></svg>
            </div>
            <div>
              <div class='card-type'>{{if
                  @model.goalType
                  @model.goalType
                  'Goal'
                }}</div>
              {{#if @model.description}}<div
                  class='card-desc'
                >{{@model.description}}</div>{{/if}}
            </div>
            {{#if @model.isCompleted}}<span class='card-done'>✓ Done</span>{{/if}}
          </div>
          <div class='card-bar-bg'>
            <div
              class='card-bar-fill'
              style={{concat 'width:' @model.progressPercent '%'}}
            ></div>
          </div>
          <div class='card-stats'>
            <span>{{if @model.currentValue @model.currentValue 0}}
              /
              {{if @model.targetValue @model.targetValue '?'}}
              {{if @model.targetUnit @model.targetUnit ''}}</span>
            <span class='card-pct'>{{if
                @model.progressPercent
                @model.progressPercent
                0
              }}%</span>
          </div>
        </div>
      </div>
      <style scoped>
        .goal-fitted {
          display: contents;
        }
        .badge,
        .strip,
        .tile,
        .card {
          display: none;
          box-sizing: border-box;
        }

        @container fitted-card (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            gap: 0.25rem;
            width: 100%;
            height: 100%;
            padding: 0.5rem;
            background: var(--card);
            color: var(--card-foreground);
            font-size: 0.625rem;
            font-weight: 600;
            text-align: center;
          }
        }
        @container fitted-card (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            align-items: center;
            justify-content: space-between;
            width: 100%;
            height: 100%;
            padding: 0 0.75rem;
            gap: 0.5rem;
            background: var(--card);
            color: var(--card-foreground);
          }
          .strip-left {
            display: flex;
            align-items: center;
            gap: 0.5rem;
          }
          .strip-info {
            display: flex;
            flex-direction: column;
          }
          .strip-type {
            font-weight: 600;
            font-size: 0.8125rem;
          }
          .strip-desc {
            font-size: 0.6875rem;
            color: var(--muted-foreground);
          }
          .strip-pct {
            font-size: 0.875rem;
            font-weight: 700;
            color: var(--primary);
          }
        }
        @container fitted-card (max-width: 399px) and (min-height: 170px) {
          .tile {
            display: flex;
            flex-direction: column;
            align-items: flex-start;
            justify-content: center;
            width: 100%;
            height: 100%;
            padding: 0.75rem;
            gap: 0.375rem;
            background: var(--card);
            color: var(--card-foreground);
          }
          .tile-header {
            display: flex;
            align-items: center;
            gap: 0.375rem;
            width: 100%;
          }
          .tile-type {
            font-weight: 600;
            font-size: 0.875rem;
            flex: 1;
          }
          .tile-done {
            color: #22c55e;
            font-size: 0.875rem;
            font-weight: 700;
          }
          .tile-progress {
            display: flex;
            align-items: center;
            gap: 0.375rem;
            width: 100%;
          }
          .tile-bar-bg {
            flex: 1;
            height: 0.375rem;
            background: var(--muted);
            border-radius: 9999px;
            overflow: hidden;
          }
          .tile-bar-fill {
            height: 100%;
            background: var(--primary);
            border-radius: 9999px;
          }
          .tile-pct {
            font-size: 0.75rem;
            font-weight: 600;
            color: var(--primary);
            min-width: 2rem;
            text-align: right;
          }
          .tile-values {
            font-size: 0.6875rem;
            color: var(--muted-foreground);
          }
        }
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .card {
            display: flex;
            flex-direction: column;
            gap: 0.5rem;
            width: 100%;
            height: 100%;
            padding: 1rem;
            background: var(--card);
            color: var(--card-foreground);
            box-sizing: border-box;
          }
          .card-header {
            display: flex;
            align-items: flex-start;
            gap: 0.625rem;
          }
          .card-icon {
            width: 2.25rem;
            height: 2.25rem;
            border-radius: 0.5rem;
            background: var(--primary);
            color: var(--primary-foreground);
            display: flex;
            align-items: center;
            justify-content: center;
            flex-shrink: 0;
          }
          .card-type {
            font-weight: 700;
            font-size: 1rem;
          }
          .card-desc {
            font-size: 0.8125rem;
            color: var(--muted-foreground);
            margin-top: 0.125rem;
          }
          .card-done {
            margin-left: auto;
            font-size: 0.75rem;
            font-weight: 600;
            color: #22c55e;
          }
          .card-bar-bg {
            height: 0.5rem;
            background: var(--muted);
            border-radius: 9999px;
            overflow: hidden;
          }
          .card-bar-fill {
            height: 100%;
            background: linear-gradient(90deg, var(--primary), var(--chart-2));
            border-radius: 9999px;
          }
          .card-stats {
            display: flex;
            justify-content: space-between;
            font-size: 0.8125rem;
            color: var(--muted-foreground);
          }
          .card-pct {
            font-weight: 600;
            color: var(--primary);
          }
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof FitnessGoal> {
    <template>
      <div class='goal-isolated'>
        <div class='gi-hero'>
          <div class='gi-icon'>
            <svg
              width='32'
              height='32'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='1.5'
            ><circle cx='12' cy='12' r='10' /><circle
                cx='12'
                cy='12'
                r='6'
              /><circle cx='12' cy='12' r='2' /></svg>
          </div>
          <div>
            <h1 class='gi-title'>{{if
                @model.goalType
                @model.goalType
                'Fitness Goal'
              }}</h1>
            {{#if @model.description}}
              <p class='gi-desc'>{{@model.description}}</p>
            {{/if}}
          </div>
          {{#if @model.isCompleted}}
            <span class='gi-complete'>✓ Completed</span>
          {{/if}}
        </div>
        <div class='gi-progress-section'>
          <h2 class='gi-section-title'>Progress</h2>
          <div class='gi-progress-bar-bg'>
            <div
              class='gi-progress-bar-fill'
              style={{concat 'width:' @model.progressPercent '%'}}
            ></div>
          </div>
          <div class='gi-progress-row'>
            <span class='gi-progress-vals'>
              Current:
              <strong>{{if @model.currentValue @model.currentValue 0}}</strong>
              / Target:
              <strong>{{if @model.targetValue @model.targetValue '—'}}</strong>
              {{if @model.targetUnit @model.targetUnit ''}}
            </span>
            <span class='gi-progress-pct'>{{if
                @model.progressPercent
                @model.progressPercent
                0
              }}%</span>
          </div>
        </div>
        <div class='gi-meta'>
          {{#if @model.deadline}}
            <div class='gi-meta-item'>
              <svg
                width='14'
                height='14'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              ><rect x='3' y='4' width='18' height='18' rx='2' ry='2' /><line
                  x1='16'
                  y1='2'
                  x2='16'
                  y2='6'
                /><line x1='8' y1='2' x2='8' y2='6' /><line
                  x1='3'
                  y1='10'
                  x2='21'
                  y2='10'
                /></svg>
              <span>Deadline: <@fields.deadline /></span>
            </div>
          {{/if}}
        </div>
        {{#if @model.notes}}
          <div class='gi-notes-section'>
            <h2 class='gi-section-title'>Notes</h2>
            <div class='gi-notes'><@fields.notes /></div>
          </div>
        {{/if}}
      </div>
      <style scoped>
        .goal-isolated {
          padding: var(--boxel-sp-xl);
          background: var(--background);
          color: var(--foreground);
          height: 100%;
          overflow-y: auto;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
          box-sizing: border-box;
        }
        .gi-hero {
          display: flex;
          align-items: flex-start;
          gap: 1rem;
        }
        .gi-icon {
          width: 4rem;
          height: 4rem;
          border-radius: 1rem;
          background: var(--primary);
          color: var(--primary-foreground);
          display: flex;
          align-items: center;
          justify-content: center;
          flex-shrink: 0;
        }
        .gi-title {
          font-size: 1.5rem;
          font-weight: 700;
          margin: 0;
        }
        .gi-desc {
          font-size: 0.9375rem;
          color: var(--muted-foreground);
          margin: 0.25rem 0 0;
        }
        .gi-complete {
          margin-left: auto;
          padding: 0.375rem 0.875rem;
          border-radius: 9999px;
          background: #22c55e20;
          color: #22c55e;
          font-weight: 600;
          font-size: 0.875rem;
        }
        .gi-section-title {
          font-size: 1rem;
          font-weight: 600;
          margin: 0 0 0.625rem;
          color: var(--foreground);
        }
        .gi-progress-bar-bg {
          height: 0.75rem;
          background: var(--muted);
          border-radius: 9999px;
          overflow: hidden;
          margin-bottom: 0.5rem;
        }
        .gi-progress-bar-fill {
          height: 100%;
          background: linear-gradient(90deg, var(--primary), var(--chart-2));
          border-radius: 9999px;
          transition: width 0.5s ease;
        }
        .gi-progress-row {
          display: flex;
          justify-content: space-between;
          align-items: center;
          font-size: 0.875rem;
          color: var(--muted-foreground);
        }
        .gi-progress-pct {
          font-weight: 700;
          font-size: 1.125rem;
          color: var(--primary);
        }
        .gi-meta {
          display: flex;
          flex-direction: column;
          gap: 0.375rem;
        }
        .gi-meta-item {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          font-size: 0.875rem;
          color: var(--muted-foreground);
        }
        .gi-notes {
          font-size: 0.9375rem;
          line-height: 1.6;
        }
      </style>
    </template>
  };
}

// ⁶ WorkoutSession CardDef
export class WorkoutSession extends CardDef {
  static displayName = 'Workout Session';
  static icon = DumbbellIcon;

  @field workoutType = contains(WorkoutTypeField);
  @field sessionDate = contains(DateField);
  @field durationMinutes = contains(NumberField);
  @field caloriesBurned = contains(NumberField);
  @field difficulty = contains(DifficultyField);
  @field exercises = containsMany(ExerciseLog);
  @field mood = contains(NumberField); // 1-5
  @field energyLevel = contains(NumberField); // 1-5
  @field notes = contains(MarkdownField);
  @field isCompleted = contains(BooleanField);

  @field totalSets = contains(NumberField, {
    computeVia: function (this: WorkoutSession) {
      try {
        if (!Array.isArray(this.exercises)) return 0;
        return this.exercises.reduce((sum: number, ex: ExerciseLog) => {
          return sum + (Array.isArray(ex?.sets) ? ex.sets.length : 0);
        }, 0);
      } catch {
        return 0;
      }
    },
  });

  @field totalVolume = contains(NumberField, {
    computeVia: function (this: WorkoutSession) {
      try {
        if (!Array.isArray(this.exercises)) return 0;
        return this.exercises.reduce((sum: number, ex: ExerciseLog) => {
          return sum + (ex?.totalVolume ?? 0);
        }, 0);
      } catch {
        return 0;
      }
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: WorkoutSession) {
      try {
        const name = this.cardInfo?.name;
        if (name) return name;
        const type = this.workoutType ?? 'Workout';
        return `${type} Session`;
      } catch {
        return 'Workout Session';
      }
    },
  });

  static embedded = class Embedded extends Component<typeof WorkoutSession> {
    <template>
      <div class='ws-embedded'>
        <div class='ws-header'>
          <div class='ws-icon'>
            <svg
              width='16'
              height='16'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            ><path d='M6 4v16M18 4v16M2 9h20M2 15h20' /></svg>
          </div>
          <div class='ws-info'>
            <span class='ws-type'>{{if
                @model.workoutType
                @model.workoutType
                'Workout'
              }}</span>
            {{#if @model.sessionDate}}
              <span class='ws-date'><@fields.sessionDate /></span>
            {{/if}}
          </div>
          {{#if @model.isCompleted}}
            <span class='ws-done'>✓</span>
          {{/if}}
        </div>
        <div class='ws-stats'>
          {{#if @model.durationMinutes}}
            <div class='ws-stat'>
              <svg
                width='12'
                height='12'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              ><circle cx='12' cy='12' r='10' /><polyline
                  points='12 6 12 12 16 14'
                /></svg>
              {{@model.durationMinutes}}
              min
            </div>
          {{/if}}
          {{#if @model.exercises.length}}
            <div class='ws-stat'>
              <svg
                width='12'
                height='12'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              ><path d='M6 4v16M18 4v16M2 9h20M2 15h20' /></svg>
              {{@model.exercises.length}}
              exercises
            </div>
          {{/if}}
          {{#if @model.caloriesBurned}}
            <div class='ws-stat'>
              <svg
                width='12'
                height='12'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              ><path
                  d='M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10 10-4.5 10-10S17.5 2 12 2zm0 14c-2.2 0-4-1.8-4-4s1.8-4 4-4 4 1.8 4 4-1.8 4-4 4z'
                /></svg>
              {{@model.caloriesBurned}}
              cal
            </div>
          {{/if}}
        </div>
      </div>
      <style scoped>
        .ws-embedded {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
          padding: 0.75rem;
          background: var(--card);
          border: 1px solid var(--border);
          border-radius: var(--radius);
        }
        .ws-header {
          display: flex;
          align-items: center;
          gap: 0.5rem;
        }
        .ws-icon {
          width: 1.75rem;
          height: 1.75rem;
          border-radius: 0.375rem;
          background: var(--primary);
          color: var(--primary-foreground);
          display: flex;
          align-items: center;
          justify-content: center;
          flex-shrink: 0;
        }
        .ws-info {
          display: flex;
          flex-direction: column;
          flex: 1;
        }
        .ws-type {
          font-weight: 600;
          font-size: 0.9375rem;
        }
        .ws-date {
          font-size: 0.75rem;
          color: var(--muted-foreground);
        }
        .ws-done {
          color: #22c55e;
          font-weight: 700;
        }
        .ws-stats {
          display: flex;
          gap: 0.75rem;
          flex-wrap: wrap;
        }
        .ws-stat {
          display: flex;
          align-items: center;
          gap: 0.25rem;
          font-size: 0.75rem;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof WorkoutSession> {
    <template>
      <div class='ws-fitted'>
        <div class='badge'>
          <svg
            width='16'
            height='16'
            viewBox='0 0 24 24'
            fill='none'
            stroke='currentColor'
            stroke-width='2'
          ><path d='M6 4v16M18 4v16M2 9h20M2 15h20' /></svg>
          <span>{{if @model.workoutType @model.workoutType 'W'}}</span>
        </div>
        <div class='strip'>
          <div class='strip-icon'>
            <svg
              width='14'
              height='14'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            ><path d='M6 4v16M18 4v16M2 9h20M2 15h20' /></svg>
          </div>
          <div class='strip-info'>
            <span class='strip-type'>{{if
                @model.workoutType
                @model.workoutType
                'Workout'
              }}</span>
            {{#if @model.durationMinutes}}<span
                class='strip-meta'
              >{{@model.durationMinutes}} min</span>{{/if}}
          </div>
          {{#if @model.isCompleted}}<span class='strip-done'>✓</span>{{/if}}
        </div>
        <div class='tile'>
          <div class='tile-top'>
            <div class='tile-icon'>
              <svg
                width='16'
                height='16'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              ><path d='M6 4v16M18 4v16M2 9h20M2 15h20' /></svg>
            </div>
            <span class='tile-type'>{{if
                @model.workoutType
                @model.workoutType
                'Workout'
              }}</span>
            {{#if @model.isCompleted}}<span class='tile-done'>✓</span>{{/if}}
          </div>
          <div class='tile-stats'>
            {{#if @model.durationMinutes}}<span
                class='tile-stat'
              >{{@model.durationMinutes}} min</span>{{/if}}
            {{#if @model.exercises.length}}<span
                class='tile-stat'
              >{{@model.exercises.length}} ex</span>{{/if}}
            {{#if @model.caloriesBurned}}<span
                class='tile-stat'
              >{{@model.caloriesBurned}} cal</span>{{/if}}
          </div>
          {{#if @model.sessionDate}}<span class='tile-date'><@fields.sessionDate
              /></span>{{/if}}
        </div>
        <div class='card'>
          <div class='card-top'>
            <div class='card-icon'>
              <svg
                width='20'
                height='20'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              ><path d='M6 4v16M18 4v16M2 9h20M2 15h20' /></svg>
            </div>
            <div class='card-title-block'>
              <span class='card-type'>{{if
                  @model.workoutType
                  @model.workoutType
                  'Workout'
                }}
                Session</span>
              {{#if @model.sessionDate}}<span
                  class='card-date'
                ><@fields.sessionDate /></span>{{/if}}
            </div>
            {{#if @model.isCompleted}}<span class='card-done'>✓ Done</span>{{/if}}
          </div>
          <div class='card-stats'>
            {{#if @model.durationMinutes}}
              <div class='card-stat'>
                <svg
                  width='12'
                  height='12'
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2'
                ><circle cx='12' cy='12' r='10' /><polyline
                    points='12 6 12 12 16 14'
                  /></svg>
                {{@model.durationMinutes}}
                min
              </div>
            {{/if}}
            {{#if @model.exercises.length}}
              <div class='card-stat'>
                <svg
                  width='12'
                  height='12'
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2'
                ><path d='M6 4v16M18 4v16M2 9h20M2 15h20' /></svg>
                {{@model.exercises.length}}
                exercises
              </div>
            {{/if}}
            {{#if @model.caloriesBurned}}
              <div class='card-stat'>
                <svg
                  width='12'
                  height='12'
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2'
                ><path
                    d='M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10 10-4.5 10-10S17.5 2 12 2zm0 14c-2.2 0-4-1.8-4-4s1.8-4 4-4 4 1.8 4 4-1.8 4-4 4z'
                  /></svg>
                {{@model.caloriesBurned}}
                kcal
              </div>
            {{/if}}
            {{#if @model.difficulty}}
              <div class='card-stat'>
                <svg
                  width='12'
                  height='12'
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2'
                ><polyline points='23 6 13.5 15.5 8.5 10.5 1 18' /><polyline
                    points='17 6 23 6 23 12'
                  /></svg>
                {{@model.difficulty}}
              </div>
            {{/if}}
          </div>
        </div>
      </div>
      <style scoped>
        .ws-fitted {
          display: contents;
        }
        .badge,
        .strip,
        .tile,
        .card {
          display: none;
          box-sizing: border-box;
        }

        @container fitted-card (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            gap: 0.25rem;
            width: 100%;
            height: 100%;
            padding: 0.5rem;
            background: var(--card);
            color: var(--card-foreground);
            font-size: 0.625rem;
            font-weight: 600;
            text-align: center;
            overflow: hidden;
          }
        }
        @container fitted-card (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            align-items: center;
            gap: 0.5rem;
            width: 100%;
            height: 100%;
            padding: 0 0.75rem;
            background: var(--card);
            color: var(--card-foreground);
          }
          .strip-icon {
            width: 1.5rem;
            height: 1.5rem;
            border-radius: 0.25rem;
            background: var(--primary);
            color: var(--primary-foreground);
            display: flex;
            align-items: center;
            justify-content: center;
            flex-shrink: 0;
          }
          .strip-info {
            display: flex;
            flex-direction: column;
            flex: 1;
          }
          .strip-type {
            font-weight: 600;
            font-size: 0.8125rem;
          }
          .strip-meta {
            font-size: 0.6875rem;
            color: var(--muted-foreground);
          }
          .strip-done {
            color: #22c55e;
            font-weight: 700;
          }
        }
        @container fitted-card (max-width: 399px) and (min-height: 170px) {
          .tile {
            display: flex;
            flex-direction: column;
            gap: 0.375rem;
            width: 100%;
            height: 100%;
            padding: 0.75rem;
            background: var(--card);
            color: var(--card-foreground);
          }
          .tile-top {
            display: flex;
            align-items: center;
            gap: 0.375rem;
          }
          .tile-icon {
            width: 1.75rem;
            height: 1.75rem;
            border-radius: 0.375rem;
            background: var(--primary);
            color: var(--primary-foreground);
            display: flex;
            align-items: center;
            justify-content: center;
          }
          .tile-type {
            font-weight: 600;
            font-size: 0.875rem;
            flex: 1;
          }
          .tile-done {
            color: #22c55e;
            font-weight: 700;
          }
          .tile-stats {
            display: flex;
            gap: 0.5rem;
            flex-wrap: wrap;
          }
          .tile-stat {
            font-size: 0.6875rem;
            padding: 0.125rem 0.375rem;
            background: var(--muted);
            border-radius: 9999px;
            color: var(--muted-foreground);
          }
          .tile-date {
            font-size: 0.6875rem;
            color: var(--muted-foreground);
            margin-top: auto;
          }
        }
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .card {
            display: flex;
            flex-direction: column;
            gap: 0.625rem;
            width: 100%;
            height: 100%;
            padding: 1rem;
            background: var(--card);
            color: var(--card-foreground);
          }
          .card-top {
            display: flex;
            align-items: flex-start;
            gap: 0.625rem;
          }
          .card-icon {
            width: 2.5rem;
            height: 2.5rem;
            border-radius: 0.5rem;
            background: var(--primary);
            color: var(--primary-foreground);
            display: flex;
            align-items: center;
            justify-content: center;
            flex-shrink: 0;
          }
          .card-title-block {
            display: flex;
            flex-direction: column;
            flex: 1;
          }
          .card-type {
            font-weight: 700;
            font-size: 1rem;
          }
          .card-date {
            font-size: 0.75rem;
            color: var(--muted-foreground);
            margin-top: 0.125rem;
          }
          .card-done {
            margin-left: auto;
            font-size: 0.75rem;
            font-weight: 600;
            color: #22c55e;
          }
          .card-stats {
            display: flex;
            flex-wrap: wrap;
            gap: 0.5rem;
          }
          .card-stat {
            display: flex;
            align-items: center;
            gap: 0.25rem;
            font-size: 0.8125rem;
            color: var(--muted-foreground);
            padding: 0.25rem 0.625rem;
            background: var(--muted);
            border-radius: 9999px;
          }
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof WorkoutSession> {
    @tracked activeTab: 'exercises' | 'stats' | 'notes' = 'exercises';

    setTab = (tab: 'exercises' | 'stats' | 'notes') => {
      this.activeTab = tab;
    };

    get moodStars() {
      const mood = this.args.model?.mood ?? 0;
      return Array.from({ length: 5 }, (_, i) => i < mood);
    }

    get energyStars() {
      const energy = this.args.model?.energyLevel ?? 0;
      return Array.from({ length: 5 }, (_, i) => i < energy);
    }

    <template>
      <div class='ws-isolated'>
        {{! Hero Section }}
        <div class='wsi-hero'>
          <div class='wsi-hero-icon'>
            <svg
              width='28'
              height='28'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='1.5'
            ><path d='M6 4v16M18 4v16M2 9h20M2 15h20' /></svg>
          </div>
          <div class='wsi-hero-info'>
            <h1 class='wsi-title'>{{if
                @model.workoutType
                @model.workoutType
                'Workout'
              }}
              Session</h1>
            {{#if @model.sessionDate}}
              <span class='wsi-date'><@fields.sessionDate /></span>
            {{/if}}
          </div>
          {{#if @model.isCompleted}}
            <span class='wsi-complete'>✓ Completed</span>
          {{else}}
            <span class='wsi-pending'>In Progress</span>
          {{/if}}
        </div>

        {{! Quick Stats }}
        <div class='wsi-stats-grid'>
          <div class='wsi-stat-card'>
            <svg
              width='20'
              height='20'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            ><circle cx='12' cy='12' r='10' /><polyline
                points='12 6 12 12 16 14'
              /></svg>
            <span class='wsi-stat-val'>{{if
                @model.durationMinutes
                @model.durationMinutes
                '—'
              }}</span>
            <span class='wsi-stat-lbl'>Minutes</span>
          </div>
          <div class='wsi-stat-card'>
            <svg
              width='20'
              height='20'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            ><path d='M6 4v16M18 4v16M2 9h20M2 15h20' /></svg>
            <span class='wsi-stat-val'>{{if
                @model.exercises.length
                @model.exercises.length
                '0'
              }}</span>
            <span class='wsi-stat-lbl'>Exercises</span>
          </div>
          <div class='wsi-stat-card'>
            <svg
              width='20'
              height='20'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            ><rect x='2' y='2' width='20' height='20' rx='2' /><path
                d='M7 12l3 3 7-7'
              /></svg>
            <span class='wsi-stat-val'>{{if
                @model.totalSets
                @model.totalSets
                '0'
              }}</span>
            <span class='wsi-stat-lbl'>Total Sets</span>
          </div>
          <div class='wsi-stat-card'>
            <svg
              width='20'
              height='20'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            ><path
                d='M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10 10-4.5 10-10S17.5 2 12 2zm0 14c-2.2 0-4-1.8-4-4s1.8-4 4-4 4 1.8 4 4-1.8 4-4 4z'
              /></svg>
            <span class='wsi-stat-val'>{{if
                @model.caloriesBurned
                @model.caloriesBurned
                '—'
              }}</span>
            <span class='wsi-stat-lbl'>Calories</span>
          </div>
          <div class='wsi-stat-card'>
            <svg
              width='20'
              height='20'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            ><polyline points='23 6 13.5 15.5 8.5 10.5 1 18' /><polyline
                points='17 6 23 6 23 12'
              /></svg>
            <span class='wsi-stat-val'>{{if
                @model.totalVolume
                @model.totalVolume
                '—'
              }}</span>
            <span class='wsi-stat-lbl'>Vol (kg)</span>
          </div>
          <div class='wsi-stat-card'>
            <svg
              width='20'
              height='20'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            ><path
                d='M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z'
              /></svg>
            <span class='wsi-stat-val'>{{if
                @model.difficulty
                @model.difficulty
                '—'
              }}</span>
            <span class='wsi-stat-lbl'>Difficulty</span>
          </div>
        </div>

        {{! Tabs }}
        <div class='wsi-tabs'>
          <button
            type='button'
            class={{if
              (eq this.activeTab 'exercises')
              'wsi-tab wsi-tab-active'
              'wsi-tab'
            }}
            {{on 'click' (fn this.setTab 'exercises')}}
          >Exercises ({{if
              @model.exercises.length
              @model.exercises.length
              0
            }})</button>
          <button
            type='button'
            class={{if
              (eq this.activeTab 'stats')
              'wsi-tab wsi-tab-active'
              'wsi-tab'
            }}
            {{on 'click' (fn this.setTab 'stats')}}
          >Stats &amp; Mood</button>
          <button
            type='button'
            class={{if
              (eq this.activeTab 'notes')
              'wsi-tab wsi-tab-active'
              'wsi-tab'
            }}
            {{on 'click' (fn this.setTab 'notes')}}
          >Notes</button>
        </div>

        {{! Exercises Tab }}
        {{#if (eq this.activeTab 'exercises')}}
          <div class='wsi-panel'>
            {{#if @model.exercises.length}}
              <div class='wsi-exercises'>
                <@fields.exercises @format='embedded' />
              </div>
            {{else}}
              <div class='wsi-empty'>
                <svg
                  width='40'
                  height='40'
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='1'
                ><path d='M6 4v16M18 4v16M2 9h20M2 15h20' /></svg>
                <p>No exercises logged yet.</p>
                <span>Switch to edit mode to add exercises.</span>
              </div>
            {{/if}}
          </div>
        {{/if}}

        {{! Stats Tab }}
        {{#if (eq this.activeTab 'stats')}}
          <div class='wsi-panel'>
            <div class='wsi-mood-section'>
              <h3 class='wsi-sub-title'>Mood</h3>
              <div class='wsi-stars'>
                {{#each this.moodStars as |filled|}}
                  <svg
                    width='20'
                    height='20'
                    viewBox='0 0 24 24'
                    fill={{if filled '#f59e0b' 'none'}}
                    stroke='#f59e0b'
                    stroke-width='2'
                  ><path
                      d='M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z'
                    /></svg>
                {{/each}}
                <span class='wsi-stars-val'>{{if @model.mood @model.mood '—'}}
                  / 5</span>
              </div>
              <h3 class='wsi-sub-title'>Energy Level</h3>
              <div class='wsi-stars'>
                {{#each this.energyStars as |filled|}}
                  <svg
                    width='20'
                    height='20'
                    viewBox='0 0 24 24'
                    fill={{if filled '#22c55e' 'none'}}
                    stroke='#22c55e'
                    stroke-width='2'
                  ><polygon
                      points='13 2 3 14 12 14 11 22 21 10 12 10 13 2'
                    /></svg>
                {{/each}}
                <span class='wsi-stars-val'>{{if
                    @model.energyLevel
                    @model.energyLevel
                    '—'
                  }}
                  / 5</span>
              </div>
            </div>
          </div>
        {{/if}}

        {{! Notes Tab }}
        {{#if (eq this.activeTab 'notes')}}
          <div class='wsi-panel'>
            {{#if @model.notes}}
              <div class='wsi-notes'><@fields.notes /></div>
            {{else}}
              <div class='wsi-empty'>
                <svg
                  width='40'
                  height='40'
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='1'
                ><path
                    d='M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z'
                  /><polyline points='14 2 14 8 20 8' /></svg>
                <p>No notes for this session.</p>
              </div>
            {{/if}}
          </div>
        {{/if}}
      </div>
      <style scoped>
        .ws-isolated {
          height: 100%;
          overflow-y: auto;
          padding: var(--boxel-sp-xl);
          background: var(--background);
          color: var(--foreground);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
          box-sizing: border-box;
        }
        .wsi-hero {
          display: flex;
          align-items: center;
          gap: 1rem;
          padding-bottom: var(--boxel-sp-lg);
          border-bottom: 1px solid var(--border);
        }
        .wsi-hero-icon {
          width: 3.5rem;
          height: 3.5rem;
          border-radius: 1rem;
          background: var(--primary);
          color: var(--primary-foreground);
          display: flex;
          align-items: center;
          justify-content: center;
          flex-shrink: 0;
        }
        .wsi-hero-info {
          flex: 1;
        }
        .wsi-title {
          font-size: 1.5rem;
          font-weight: 700;
          margin: 0;
        }
        .wsi-date {
          font-size: 0.875rem;
          color: var(--muted-foreground);
        }
        .wsi-complete {
          padding: 0.375rem 0.875rem;
          border-radius: 9999px;
          background: #22c55e20;
          color: #22c55e;
          font-weight: 600;
          font-size: 0.875rem;
        }
        .wsi-pending {
          padding: 0.375rem 0.875rem;
          border-radius: 9999px;
          background: var(--muted);
          color: var(--muted-foreground);
          font-weight: 600;
          font-size: 0.875rem;
        }
        .wsi-stats-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(8rem, 1fr));
          gap: var(--boxel-sp);
        }
        .wsi-stat-card {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 0.25rem;
          padding: 0.875rem 0.5rem;
          background: var(--card);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          box-shadow: var(--shadow-sm);
          color: var(--muted-foreground);
          text-align: center;
        }
        .wsi-stat-val {
          font-size: 1.25rem;
          font-weight: 700;
          color: var(--foreground);
          line-height: 1;
        }
        .wsi-stat-lbl {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
          font-weight: 500;
        }
        .wsi-tabs {
          display: flex;
          border-bottom: 2px solid var(--border);
          gap: 0;
        }
        .wsi-tab {
          padding: 0.5rem 1.25rem;
          border: none;
          background: transparent;
          cursor: pointer;
          font-size: 0.875rem;
          font-weight: 500;
          color: var(--muted-foreground);
          border-bottom: 2px solid transparent;
          margin-bottom: -2px;
          transition:
            color 0.15s,
            border-color 0.15s;
        }
        .wsi-tab:hover {
          color: var(--foreground);
        }
        .wsi-tab-active {
          color: var(--primary);
          border-bottom-color: var(--primary);
        }
        .wsi-panel {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
        }
        .wsi-exercises > .containsMany-field {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
        }
        .wsi-empty {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 0.5rem;
          padding: 2.5rem 1rem;
          color: var(--muted-foreground);
          text-align: center;
        }
        .wsi-empty p {
          font-weight: 500;
          margin: 0;
        }
        .wsi-empty span {
          font-size: 0.8125rem;
        }
        .wsi-mood-section {
          display: flex;
          flex-direction: column;
          gap: 0.75rem;
        }
        .wsi-sub-title {
          font-size: 0.9375rem;
          font-weight: 600;
          margin: 0;
        }
        .wsi-stars {
          display: flex;
          align-items: center;
          gap: 0.25rem;
        }
        .wsi-stars-val {
          font-size: 0.875rem;
          color: var(--muted-foreground);
          margin-left: 0.5rem;
        }
        .wsi-notes {
          font-size: 0.9375rem;
          line-height: 1.6;
        }
      </style>
    </template>
  };
}

// ⁷ WorkoutTracker Dashboard CardDef
export class WorkoutTracker extends CardDef {
  static displayName = 'Workout Tracker';
  static icon = ActivityIcon;
  static prefersWideFormat = true;

  @field trackerName = contains(StringField);
  @field recentSessions = linksToMany(() => WorkoutSession);
  @field goals = linksToMany(() => FitnessGoal);
  @field weeklyTargetDays = contains(NumberField);
  @field weeklyTargetMinutes = contains(NumberField);
  @field notes = contains(MarkdownField);

  @field totalWorkouts = contains(NumberField, {
    computeVia: function (this: WorkoutTracker) {
      try {
        return Array.isArray(this.recentSessions)
          ? this.recentSessions.length
          : 0;
      } catch {
        return 0;
      }
    },
  });

  @field completedWorkouts = contains(NumberField, {
    computeVia: function (this: WorkoutTracker) {
      try {
        if (!Array.isArray(this.recentSessions)) return 0;
        return this.recentSessions.filter((s: WorkoutSession) => s?.isCompleted)
          .length;
      } catch {
        return 0;
      }
    },
  });

  @field totalMinutes = contains(NumberField, {
    computeVia: function (this: WorkoutTracker) {
      try {
        if (!Array.isArray(this.recentSessions)) return 0;
        return this.recentSessions.reduce((sum: number, s: WorkoutSession) => {
          return sum + (s?.durationMinutes ?? 0);
        }, 0);
      } catch {
        return 0;
      }
    },
  });

  @field totalCalories = contains(NumberField, {
    computeVia: function (this: WorkoutTracker) {
      try {
        if (!Array.isArray(this.recentSessions)) return 0;
        return this.recentSessions.reduce((sum: number, s: WorkoutSession) => {
          return sum + (s?.caloriesBurned ?? 0);
        }, 0);
      } catch {
        return 0;
      }
    },
  });

  @field activeGoals = contains(NumberField, {
    computeVia: function (this: WorkoutTracker) {
      try {
        if (!Array.isArray(this.goals)) return 0;
        return this.goals.filter((g: FitnessGoal) => !g?.isCompleted).length;
      } catch {
        return 0;
      }
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: WorkoutTracker) {
      return this.cardInfo?.name ?? this.trackerName ?? 'Workout Tracker';
    },
  });

  static embedded = class Embedded extends Component<typeof WorkoutTracker> {
    <template>
      <div class='wt-embedded'>
        <div class='wte-header'>
          <svg
            width='18'
            height='18'
            viewBox='0 0 24 24'
            fill='none'
            stroke='currentColor'
            stroke-width='2'
          ><polyline points='22 12 18 12 15 21 9 3 6 12 2 12' /></svg>
          <span>{{if
              @model.trackerName
              @model.trackerName
              'Workout Tracker'
            }}</span>
        </div>
        <div class='wte-stats'>
          <span>{{if @model.totalWorkouts @model.totalWorkouts 0}}
            sessions</span>
          <span>{{if @model.totalMinutes @model.totalMinutes 0}} min</span>
          <span>{{if @model.activeGoals @model.activeGoals 0}} goals</span>
        </div>
      </div>
      <style scoped>
        .wt-embedded {
          display: flex;
          flex-direction: column;
          gap: 0.375rem;
          padding: 0.75rem;
          background: var(--card);
          border: 1px solid var(--border);
          border-radius: var(--radius);
        }
        .wte-header {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          font-weight: 600;
        }
        .wte-stats {
          display: flex;
          gap: 0.75rem;
          font-size: 0.8125rem;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof WorkoutTracker> {
    <template>
      <div class='wt-fitted'>
        <div class='badge'>
          <svg
            width='18'
            height='18'
            viewBox='0 0 24 24'
            fill='none'
            stroke='currentColor'
            stroke-width='2'
          ><polyline points='22 12 18 12 15 21 9 3 6 12 2 12' /></svg>
        </div>
        <div class='strip'>
          <svg
            width='16'
            height='16'
            viewBox='0 0 24 24'
            fill='none'
            stroke='currentColor'
            stroke-width='2'
          ><polyline points='22 12 18 12 15 21 9 3 6 12 2 12' /></svg>
          <span class='strip-name'>{{if
              @model.trackerName
              @model.trackerName
              'Tracker'
            }}</span>
          <span class='strip-stats'>{{if
              @model.totalWorkouts
              @model.totalWorkouts
              0
            }}
            sessions</span>
        </div>
        <div class='tile'>
          <div class='tile-top'>
            <svg
              width='18'
              height='18'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            ><polyline points='22 12 18 12 15 21 9 3 6 12 2 12' /></svg>
            <span class='tile-name'>{{if
                @model.trackerName
                @model.trackerName
                'Workout Tracker'
              }}</span>
          </div>
          <div class='tile-grid'>
            <div class='tile-stat'><span class='tile-val'>{{if
                  @model.totalWorkouts
                  @model.totalWorkouts
                  0
                }}</span><span class='tile-lbl'>Sessions</span></div>
            <div class='tile-stat'><span class='tile-val'>{{if
                  @model.totalMinutes
                  @model.totalMinutes
                  0
                }}</span><span class='tile-lbl'>Min</span></div>
            <div class='tile-stat'><span class='tile-val'>{{if
                  @model.activeGoals
                  @model.activeGoals
                  0
                }}</span><span class='tile-lbl'>Goals</span></div>
          </div>
        </div>
        <div class='card'>
          <div class='card-header'>
            <div class='card-icon'>
              <svg
                width='20'
                height='20'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              ><polyline points='22 12 18 12 15 21 9 3 6 12 2 12' /></svg>
            </div>
            <span class='card-name'>{{if
                @model.trackerName
                @model.trackerName
                'Workout Tracker'
              }}</span>
          </div>
          <div class='card-grid'>
            <div class='card-stat'><span class='card-val'>{{if
                  @model.totalWorkouts
                  @model.totalWorkouts
                  0
                }}</span><span class='card-lbl'>Sessions</span></div>
            <div class='card-stat'><span class='card-val'>{{if
                  @model.completedWorkouts
                  @model.completedWorkouts
                  0
                }}</span><span class='card-lbl'>Completed</span></div>
            <div class='card-stat'><span class='card-val'>{{if
                  @model.totalMinutes
                  @model.totalMinutes
                  0
                }}</span><span class='card-lbl'>Minutes</span></div>
            <div class='card-stat'><span class='card-val'>{{if
                  @model.totalCalories
                  @model.totalCalories
                  0
                }}</span><span class='card-lbl'>Calories</span></div>
            <div class='card-stat'><span class='card-val'>{{if
                  @model.activeGoals
                  @model.activeGoals
                  0
                }}</span><span class='card-lbl'>Active Goals</span></div>
          </div>
        </div>
      </div>
      <style scoped>
        .wt-fitted {
          display: contents;
        }
        .badge,
        .strip,
        .tile,
        .card {
          display: none;
          box-sizing: border-box;
        }

        @container fitted-card (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            align-items: center;
            justify-content: center;
            width: 100%;
            height: 100%;
            background: var(--card);
            color: var(--primary);
          }
        }
        @container fitted-card (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            align-items: center;
            gap: 0.625rem;
            width: 100%;
            height: 100%;
            padding: 0 0.875rem;
            background: var(--card);
            color: var(--card-foreground);
          }
          .strip-name {
            font-weight: 600;
            font-size: 0.875rem;
            flex: 1;
          }
          .strip-stats {
            font-size: 0.75rem;
            color: var(--muted-foreground);
          }
        }
        @container fitted-card (max-width: 399px) and (min-height: 170px) {
          .tile {
            display: flex;
            flex-direction: column;
            gap: 0.5rem;
            width: 100%;
            height: 100%;
            padding: 0.875rem;
            background: var(--card);
            color: var(--card-foreground);
          }
          .tile-top {
            display: flex;
            align-items: center;
            gap: 0.375rem;
          }
          .tile-name {
            font-weight: 600;
            font-size: 0.875rem;
          }
          .tile-grid {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 0.375rem;
          }
          .tile-stat {
            display: flex;
            flex-direction: column;
            align-items: center;
            padding: 0.375rem;
            background: var(--muted);
            border-radius: 0.375rem;
          }
          .tile-val {
            font-size: 1rem;
            font-weight: 700;
            color: var(--primary);
          }
          .tile-lbl {
            font-size: 0.5625rem;
            color: var(--muted-foreground);
            font-weight: 500;
          }
        }
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .card {
            display: flex;
            flex-direction: column;
            gap: 0.75rem;
            width: 100%;
            height: 100%;
            padding: 1rem;
            background: var(--card);
            color: var(--card-foreground);
          }
          .card-header {
            display: flex;
            align-items: center;
            gap: 0.625rem;
          }
          .card-icon {
            width: 2.25rem;
            height: 2.25rem;
            border-radius: 0.5rem;
            background: var(--primary);
            color: var(--primary-foreground);
            display: flex;
            align-items: center;
            justify-content: center;
          }
          .card-name {
            font-weight: 700;
            font-size: 1rem;
          }
          .card-grid {
            display: grid;
            grid-template-columns: repeat(5, 1fr);
            gap: 0.5rem;
          }
          .card-stat {
            display: flex;
            flex-direction: column;
            align-items: center;
            padding: 0.5rem 0.25rem;
            background: var(--muted);
            border-radius: 0.5rem;
          }
          .card-val {
            font-size: 1.125rem;
            font-weight: 700;
            color: var(--primary);
          }
          .card-lbl {
            font-size: 0.625rem;
            color: var(--muted-foreground);
            font-weight: 500;
            text-align: center;
          }
        }
      </style>
    </template>
  };

  // ⁸ Isolated: full dashboard with recent sessions, goals, and bar chart
  static isolated = class Isolated extends Component<typeof WorkoutTracker> {
    @tracked activeSection: 'dashboard' | 'sessions' | 'goals' = 'dashboard';

    setSection = (s: 'dashboard' | 'sessions' | 'goals') => {
      this.activeSection = s;
    };

    get weeklyProgress() {
      try {
        const target = this.args.model?.weeklyTargetDays ?? 5;
        const completed = this.args.model?.completedWorkouts ?? 0;
        const pct = Math.min(100, Math.round((completed / target) * 100));
        return { target, completed, pct };
      } catch {
        return { target: 5, completed: 0, pct: 0 };
      }
    }

    get chartData() {
      try {
        const sessions = this.args.model?.recentSessions;
        if (!Array.isArray(sessions) || !sessions.length) return [];
        return sessions.slice(-7).map((s: WorkoutSession, i: number) => ({
          label: s?.workoutType ?? `S${i + 1}`,
          duration: s?.durationMinutes ?? 0,
          calories: s?.caloriesBurned ?? 0,
          max: 120,
        }));
      } catch {
        return [];
      }
    }

    get maxDuration() {
      try {
        const data = this.chartData;
        if (!data.length) return 60;
        return Math.max(...data.map((d) => d.duration), 60);
      } catch {
        return 60;
      }
    }

    <template>
      <div class='wt-isolated'>
        {{! Header }}
        <div class='wti-header'>
          <div class='wti-header-left'>
            <div class='wti-icon'>
              <svg
                width='28'
                height='28'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='1.5'
              ><polyline points='22 12 18 12 15 21 9 3 6 12 2 12' /></svg>
            </div>
            <div>
              <h1 class='wti-title'>{{if
                  @model.trackerName
                  @model.trackerName
                  'Workout Tracker'
                }}</h1>
              <p class='wti-subtitle'>Track progress. Crush goals. Stay
                consistent.</p>
            </div>
          </div>
        </div>

        {{! KPI Row }}
        <div class='wti-kpi-row'>
          <div class='wti-kpi'>
            <div class='wti-kpi-icon wti-kpi-blue'>
              <svg
                width='16'
                height='16'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              ><path d='M6 4v16M18 4v16M2 9h20M2 15h20' /></svg>
            </div>
            <div>
              <div class='wti-kpi-val'>{{if
                  @model.totalWorkouts
                  @model.totalWorkouts
                  0
                }}</div>
              <div class='wti-kpi-lbl'>Total Sessions</div>
            </div>
          </div>
          <div class='wti-kpi'>
            <div class='wti-kpi-icon wti-kpi-green'>
              <svg
                width='16'
                height='16'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              ><rect x='2' y='2' width='20' height='20' rx='2' /><path
                  d='M7 12l3 3 7-7'
                /></svg>
            </div>
            <div>
              <div class='wti-kpi-val'>{{if
                  @model.completedWorkouts
                  @model.completedWorkouts
                  0
                }}</div>
              <div class='wti-kpi-lbl'>Completed</div>
            </div>
          </div>
          <div class='wti-kpi'>
            <div class='wti-kpi-icon wti-kpi-orange'>
              <svg
                width='16'
                height='16'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              ><circle cx='12' cy='12' r='10' /><polyline
                  points='12 6 12 12 16 14'
                /></svg>
            </div>
            <div>
              <div class='wti-kpi-val'>{{if
                  @model.totalMinutes
                  @model.totalMinutes
                  0
                }}</div>
              <div class='wti-kpi-lbl'>Total Minutes</div>
            </div>
          </div>
          <div class='wti-kpi'>
            <div class='wti-kpi-icon wti-kpi-red'>
              <svg
                width='16'
                height='16'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              ><path
                  d='M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10 10-4.5 10-10S17.5 2 12 2zm0 14c-2.2 0-4-1.8-4-4s1.8-4 4-4 4 1.8 4 4-1.8 4-4 4z'
                /></svg>
            </div>
            <div>
              <div class='wti-kpi-val'>{{if
                  @model.totalCalories
                  @model.totalCalories
                  0
                }}</div>
              <div class='wti-kpi-lbl'>Calories Burned</div>
            </div>
          </div>
          <div class='wti-kpi'>
            <div class='wti-kpi-icon wti-kpi-purple'>
              <svg
                width='16'
                height='16'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              ><circle cx='12' cy='12' r='10' /><circle
                  cx='12'
                  cy='12'
                  r='6'
                /><circle cx='12' cy='12' r='2' /></svg>
            </div>
            <div>
              <div class='wti-kpi-val'>{{if
                  @model.activeGoals
                  @model.activeGoals
                  0
                }}</div>
              <div class='wti-kpi-lbl'>Active Goals</div>
            </div>
          </div>
        </div>

        {{! Nav }}
        <div class='wti-nav'>
          <button
            type='button'
            class={{if
              (eq this.activeSection 'dashboard')
              'wti-nav-btn wti-nav-active'
              'wti-nav-btn'
            }}
            {{on 'click' (fn this.setSection 'dashboard')}}
          >
            <svg
              width='14'
              height='14'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            ><rect x='3' y='3' width='7' height='7' /><rect
                x='14'
                y='3'
                width='7'
                height='7'
              /><rect x='14' y='14' width='7' height='7' /><rect
                x='3'
                y='14'
                width='7'
                height='7'
              /></svg>
            Dashboard
          </button>
          <button
            type='button'
            class={{if
              (eq this.activeSection 'sessions')
              'wti-nav-btn wti-nav-active'
              'wti-nav-btn'
            }}
            {{on 'click' (fn this.setSection 'sessions')}}
          >
            <svg
              width='14'
              height='14'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            ><path d='M6 4v16M18 4v16M2 9h20M2 15h20' /></svg>
            Sessions ({{if @model.totalWorkouts @model.totalWorkouts 0}})
          </button>
          <button
            type='button'
            class={{if
              (eq this.activeSection 'goals')
              'wti-nav-btn wti-nav-active'
              'wti-nav-btn'
            }}
            {{on 'click' (fn this.setSection 'goals')}}
          >
            <svg
              width='14'
              height='14'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            ><circle cx='12' cy='12' r='10' /><circle
                cx='12'
                cy='12'
                r='6'
              /><circle cx='12' cy='12' r='2' /></svg>
            Goals ({{if @model.goals.length @model.goals.length 0}})
          </button>
        </div>

        {{! Dashboard Section }}
        {{#if (eq this.activeSection 'dashboard')}}
          <div class='wti-body'>
            <div class='wti-main'>
              {{! Progress Chart }}
              <section class='wti-chart-section'>
                <h2 class='wti-section-title'>
                  <svg
                    width='16'
                    height='16'
                    viewBox='0 0 24 24'
                    fill='none'
                    stroke='currentColor'
                    stroke-width='2'
                  ><polyline points='23 6 13.5 15.5 8.5 10.5 1 18' /><polyline
                      points='17 6 23 6 23 12'
                    /></svg>
                  Recent Session Activity
                </h2>
                {{#if this.chartData.length}}
                  <div class='wti-chart'>
                    {{#each this.chartData as |bar|}}
                      <div class='chart-bar-group'>
                        <div class='chart-bar-wrap'>
                          <div
                            class='chart-bar-duration'
                            style={{concat
                              'height:'
                              (if
                                bar.duration
                                (concat
                                  (multiply
                                    (divide bar.duration this.maxDuration) 100
                                  )
                                  '%'
                                )
                                '0%'
                              )
                            }}
                          ></div>
                        </div>
                        <span class='chart-bar-label'>{{bar.label}}</span>
                        <span class='chart-bar-val'>{{bar.duration}}m</span>
                      </div>
                    {{/each}}
                  </div>
                  <div class='chart-legend'>
                    <span
                      class='chart-legend-dot chart-legend-blue'
                    ></span>Duration (min)
                  </div>
                {{else}}
                  <div class='wti-empty-chart'>
                    <svg
                      width='32'
                      height='32'
                      viewBox='0 0 24 24'
                      fill='none'
                      stroke='currentColor'
                      stroke-width='1.5'
                    ><polyline points='23 6 13.5 15.5 8.5 10.5 1 18' /></svg>
                    <p>No session data yet. Add workout sessions to see your
                      progress chart.</p>
                  </div>
                {{/if}}
              </section>

              {{! Weekly Progress }}
              <section class='wti-weekly-section'>
                <h2 class='wti-section-title'>
                  <svg
                    width='16'
                    height='16'
                    viewBox='0 0 24 24'
                    fill='none'
                    stroke='currentColor'
                    stroke-width='2'
                  ><rect x='3' y='4' width='18' height='18' rx='2' /><line
                      x1='16'
                      y1='2'
                      x2='16'
                      y2='6'
                    /><line x1='8' y1='2' x2='8' y2='6' /><line
                      x1='3'
                      y1='10'
                      x2='21'
                      y2='10'
                    /></svg>
                  Weekly Progress
                </h2>
                <div class='wti-weekly-bar-bg'>
                  <div
                    class='wti-weekly-bar-fill'
                    style={{concat 'width:' this.weeklyProgress.pct '%'}}
                  ></div>
                </div>
                <div class='wti-weekly-labels'>
                  <span>{{this.weeklyProgress.completed}}
                    /
                    {{this.weeklyProgress.target}}
                    sessions</span>
                  <span
                    class='wti-weekly-pct'
                  >{{this.weeklyProgress.pct}}%</span>
                </div>
                {{#if @model.weeklyTargetMinutes}}
                  <p class='wti-weekly-note'>Target:
                    {{@model.weeklyTargetMinutes}}
                    min/week · Current:
                    {{if @model.totalMinutes @model.totalMinutes 0}}
                    min</p>
                {{/if}}
              </section>
            </div>

            {{! Sidebar: Goals preview }}
            <aside class='wti-sidebar'>
              <section class='wti-sidebar-section'>
                <h2 class='wti-sidebar-title'>Active Goals</h2>
                {{#if @model.goals.length}}
                  <div class='wti-goals-list'>
                    <@fields.goals @format='embedded' />
                  </div>
                {{else}}
                  <div class='wti-empty-sm'>
                    <svg
                      width='24'
                      height='24'
                      viewBox='0 0 24 24'
                      fill='none'
                      stroke='currentColor'
                      stroke-width='1.5'
                    ><circle cx='12' cy='12' r='10' /><circle
                        cx='12'
                        cy='12'
                        r='6'
                      /><circle cx='12' cy='12' r='2' /></svg>
                    <p>No goals set yet.</p>
                  </div>
                {{/if}}
              </section>

              <section class='wti-sidebar-section'>
                <h2 class='wti-sidebar-title'>Recent Sessions</h2>
                {{#if @model.recentSessions.length}}
                  <div class='wti-sessions-list'>
                    <@fields.recentSessions @format='embedded' />
                  </div>
                {{else}}
                  <div class='wti-empty-sm'>
                    <svg
                      width='24'
                      height='24'
                      viewBox='0 0 24 24'
                      fill='none'
                      stroke='currentColor'
                      stroke-width='1.5'
                    ><path d='M6 4v16M18 4v16M2 9h20M2 15h20' /></svg>
                    <p>No sessions logged.</p>
                  </div>
                {{/if}}
              </section>
            </aside>
          </div>
        {{/if}}

        {{! Sessions Section }}
        {{#if (eq this.activeSection 'sessions')}}
          <div class='wti-full-list'>
            <h2 class='wti-section-title'>
              <svg
                width='16'
                height='16'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              ><path d='M6 4v16M18 4v16M2 9h20M2 15h20' /></svg>
              All Workout Sessions
            </h2>
            {{#if @model.recentSessions.length}}
              <div class='wti-sessions-grid'>
                <@fields.recentSessions @format='embedded' />
              </div>
            {{else}}
              <div class='wti-empty'>
                <svg
                  width='40'
                  height='40'
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='1'
                ><path d='M6 4v16M18 4v16M2 9h20M2 15h20' /></svg>
                <p>No workout sessions logged yet.</p>
                <span>Create WorkoutSession cards and link them here.</span>
              </div>
            {{/if}}
          </div>
        {{/if}}

        {{! Goals Section }}
        {{#if (eq this.activeSection 'goals')}}
          <div class='wti-full-list'>
            <h2 class='wti-section-title'>
              <svg
                width='16'
                height='16'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              ><circle cx='12' cy='12' r='10' /><circle
                  cx='12'
                  cy='12'
                  r='6'
                /><circle cx='12' cy='12' r='2' /></svg>
              All Fitness Goals
            </h2>
            {{#if @model.goals.length}}
              <div class='wti-goals-grid'>
                <@fields.goals @format='embedded' />
              </div>
            {{else}}
              <div class='wti-empty'>
                <svg
                  width='40'
                  height='40'
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='1'
                ><circle cx='12' cy='12' r='10' /><circle
                    cx='12'
                    cy='12'
                    r='6'
                  /><circle cx='12' cy='12' r='2' /></svg>
                <p>No fitness goals set yet.</p>
                <span>Create FitnessGoal cards and link them here.</span>
              </div>
            {{/if}}
          </div>
        {{/if}}
      </div>
      <style scoped>
        .wt-isolated {
          height: 100%;
          overflow-y: auto;
          padding: var(--boxel-sp-xl);
          background: var(--background);
          color: var(--foreground);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
          box-sizing: border-box;
          font-family: var(--font-sans, system-ui, sans-serif);
        }
        .wti-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding-bottom: var(--boxel-sp-lg);
          border-bottom: 1px solid var(--border);
        }
        .wti-header-left {
          display: flex;
          align-items: center;
          gap: 1rem;
        }
        .wti-icon {
          width: 3.5rem;
          height: 3.5rem;
          border-radius: 1rem;
          background: var(--primary);
          color: var(--primary-foreground);
          display: flex;
          align-items: center;
          justify-content: center;
          flex-shrink: 0;
        }
        .wti-title {
          font-size: 1.75rem;
          font-weight: 800;
          margin: 0;
          letter-spacing: -0.02em;
        }
        .wti-subtitle {
          font-size: 0.9375rem;
          color: var(--muted-foreground);
          margin: 0.25rem 0 0;
        }

        .wti-kpi-row {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(9rem, 1fr));
          gap: var(--boxel-sp);
        }
        .wti-kpi {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          padding: 1rem;
          background: var(--card);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          box-shadow: var(--shadow-sm);
        }
        .wti-kpi-icon {
          width: 2.25rem;
          height: 2.25rem;
          border-radius: 0.5rem;
          display: flex;
          align-items: center;
          justify-content: center;
          flex-shrink: 0;
        }
        .wti-kpi-blue {
          background: #3b82f620;
          color: #3b82f6;
        }
        .wti-kpi-green {
          background: #22c55e20;
          color: #22c55e;
        }
        .wti-kpi-orange {
          background: #f97316.20;
          color: #f97316;
        }
        .wti-kpi-red {
          background: #ef444420;
          color: #ef4444;
        }
        .wti-kpi-purple {
          background: #a855f720;
          color: #a855f7;
        }
        .wti-kpi-orange {
          background: rgba(249, 115, 22, 0.15);
          color: #f97316;
        }
        .wti-kpi-red {
          background: rgba(239, 68, 68, 0.15);
          color: #ef4444;
        }
        .wti-kpi-val {
          font-size: 1.5rem;
          font-weight: 800;
          color: var(--foreground);
          line-height: 1;
        }
        .wti-kpi-lbl {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
          font-weight: 500;
          margin-top: 0.125rem;
        }

        .wti-nav {
          display: flex;
          gap: 0;
          border-bottom: 2px solid var(--border);
        }
        .wti-nav-btn {
          display: flex;
          align-items: center;
          gap: 0.375rem;
          padding: 0.625rem 1.25rem;
          border: none;
          background: transparent;
          cursor: pointer;
          font-size: 0.875rem;
          font-weight: 500;
          color: var(--muted-foreground);
          border-bottom: 2px solid transparent;
          margin-bottom: -2px;
          transition:
            color 0.15s,
            border-color 0.15s;
        }
        .wti-nav-btn:hover {
          color: var(--foreground);
        }
        .wti-nav-active {
          color: var(--primary);
          border-bottom-color: var(--primary);
        }

        .wti-body {
          display: grid;
          grid-template-columns: 1fr 22rem;
          gap: var(--boxel-sp-lg);
          align-items: start;
        }
        .wti-main {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
        }
        .wti-section-title {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          font-size: 1rem;
          font-weight: 600;
          margin: 0 0 0.75rem;
          color: var(--foreground);
        }
        .wti-chart-section,
        .wti-weekly-section {
          background: var(--card);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          padding: 1.25rem;
          box-shadow: var(--shadow-sm);
        }

        /* Bar chart */
        .wti-chart {
          display: flex;
          align-items: flex-end;
          gap: 0.5rem;
          height: 10rem;
          padding-bottom: 1.5rem;
          position: relative;
        }
        .chart-bar-group {
          display: flex;
          flex-direction: column;
          align-items: center;
          flex: 1;
          height: 100%;
          justify-content: flex-end;
          gap: 0.25rem;
        }
        .chart-bar-wrap {
          width: 100%;
          flex: 1;
          display: flex;
          align-items: flex-end;
        }
        .chart-bar-duration {
          width: 100%;
          min-height: 4px;
          background: linear-gradient(180deg, var(--primary), var(--chart-2));
          border-radius: 0.25rem 0.25rem 0 0;
          transition: height 0.4s ease;
        }
        .chart-bar-label {
          font-size: 0.625rem;
          color: var(--muted-foreground);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
          max-width: 100%;
        }
        .chart-bar-val {
          font-size: 0.5625rem;
          color: var(--primary);
          font-weight: 600;
        }
        .chart-legend {
          display: flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.75rem;
          color: var(--muted-foreground);
          margin-top: 0.5rem;
        }
        .chart-legend-dot {
          width: 0.625rem;
          height: 0.625rem;
          border-radius: 9999px;
        }
        .chart-legend-blue {
          background: var(--primary);
        }
        .wti-empty-chart {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 0.5rem;
          padding: 2rem;
          color: var(--muted-foreground);
          text-align: center;
        }
        .wti-empty-chart p {
          font-size: 0.875rem;
          margin: 0;
        }

        /* Weekly bar */
        .wti-weekly-bar-bg {
          height: 0.625rem;
          background: var(--muted);
          border-radius: 9999px;
          overflow: hidden;
          margin-bottom: 0.375rem;
        }
        .wti-weekly-bar-fill {
          height: 100%;
          background: linear-gradient(90deg, var(--primary), var(--chart-2));
          border-radius: 9999px;
          transition: width 0.5s ease;
        }
        .wti-weekly-labels {
          display: flex;
          justify-content: space-between;
          font-size: 0.8125rem;
          color: var(--muted-foreground);
        }
        .wti-weekly-pct {
          font-weight: 700;
          color: var(--primary);
        }
        .wti-weekly-note {
          font-size: 0.75rem;
          color: var(--muted-foreground);
          margin: 0.375rem 0 0;
        }

        /* Sidebar */
        .wti-sidebar {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
          background: var(--sidebar);
          border: 1px solid var(--sidebar-border);
          border-radius: var(--radius);
          padding: var(--boxel-sp);
        }
        .wti-sidebar-section {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }
        .wti-sidebar-section + .wti-sidebar-section {
          border-top: 1px solid var(--sidebar-border);
          padding-top: var(--boxel-sp);
        }
        .wti-sidebar-title {
          font-size: 0.8125rem;
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.05em;
          color: var(--sidebar-foreground);
          margin: 0;
        }
        .wti-goals-list > .containsMany-field,
        .wti-sessions-list > .containsMany-field {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }
        .wti-empty-sm {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          padding: 0.75rem;
          color: var(--muted-foreground);
          font-size: 0.8125rem;
        }
        .wti-empty-sm p {
          margin: 0;
        }

        /* Full list view */
        .wti-full-list {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
        }
        .wti-sessions-grid > .containsMany-field,
        .wti-goals-grid > .containsMany-field {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(22rem, 1fr));
          gap: var(--boxel-sp);
        }
        .wti-empty {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 0.5rem;
          padding: 3rem 1rem;
          color: var(--muted-foreground);
          text-align: center;
          background: var(--card);
          border: 1px dashed var(--border);
          border-radius: var(--radius);
        }
        .wti-empty p {
          font-weight: 500;
          margin: 0;
        }
        .wti-empty span {
          font-size: 0.8125rem;
        }

        @container (max-width: 700px) {
          .wti-body {
            grid-template-columns: 1fr;
          }
          .wti-kpi-row {
            grid-template-columns: repeat(2, 1fr);
          }
          .wti-sessions-grid > .containsMany-field,
          .wti-goals-grid > .containsMany-field {
            grid-template-columns: 1fr;
          }
        }
      </style>
    </template>
  };
}
