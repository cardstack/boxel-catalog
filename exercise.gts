// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
import {
  CardDef,
  FieldDef,
  field,
  contains,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import TextAreaField from 'https://cardstack.com/base/text-area';

export class MuscleGroupField extends FieldDef {
  static displayName = 'Muscle Group';
  @field name = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='muscle-group'>{{@model.name}}</span>
    </template>
  };
}

export class ExerciseSetField extends FieldDef {
  static displayName = 'Exercise Set';
  @field sets = contains(NumberField);
  @field reps = contains(NumberField);
  @field weight = contains(NumberField);
  @field notes = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='exercise-set'>
        <span>{{@model.sets}} sets x {{@model.reps}} reps</span>
        {{#if @model.weight}}
          <span> @ {{@model.weight}} kg</span>
        {{/if}}
      </div>
    </template>
  };
}

export class Exercise extends CardDef {
  static displayName = 'Exercise';
  @field name = contains(StringField);
  @field muscleGroup = contains(StringField);
  @field equipment = contains(StringField);
  @field personalRecord = contains(NumberField);
  @field notes = contains(TextAreaField);

  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <div class='exercise-card'>
        <h1>{{@model.name}}</h1>
        <div class='details'>
          <div class='detail-row'>
            <span class='label'>Muscle Group:</span>
            <span>{{@model.muscleGroup}}</span>
          </div>
          <div class='detail-row'>
            <span class='label'>Equipment:</span>
            <span>{{@model.equipment}}</span>
          </div>
          {{#if @model.personalRecord}}
            <div class='detail-row'>
              <span class='label'>Personal Record:</span>
              <span>{{@model.personalRecord}} kg</span>
            </div>
          {{/if}}
          {{#if @model.notes}}
            <div class='detail-row'>
              <span class='label'>Notes:</span>
              <span>{{@model.notes}}</span>
            </div>
          {{/if}}
        </div>
      </div>
      <style scoped>
        .exercise-card { padding: 2rem; font-family: sans-serif; }
        h1 { font-size: 1.8rem; margin-bottom: 1rem; color: #1a1a2e; }
        .details { display: flex; flex-direction: column; gap: 0.75rem; }
        .detail-row { display: flex; gap: 0.5rem; }
        .label { font-weight: bold; color: #555; min-width: 140px; }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='exercise-embedded'>
        <span class='name'>{{@model.name}}</span>
        <span class='muscle'>{{@model.muscleGroup}}</span>
      </div>
      <style scoped>
        .exercise-embedded { display: flex; justify-content: space-between; padding: 0.5rem; }
        .name { font-weight: bold; }
        .muscle { color: #888; font-size: 0.85rem; }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <div class='exercise-fitted'>
        <span class='name'>{{@model.name}}</span>
        <span class='muscle'>{{@model.muscleGroup}}</span>
      </div>
      <style scoped>
        .exercise-fitted { padding: 0.5rem; }
        .name { font-weight: bold; display: block; }
        .muscle { color: #888; font-size: 0.8rem; }
      </style>
    </template>
  };
}
