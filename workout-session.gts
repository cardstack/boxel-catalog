// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
import {
  CardDef,
  FieldDef,
  field,
  contains,
  containsMany,
  linksTo,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import DateField from 'https://cardstack.com/base/date';
import TextAreaField from 'https://cardstack.com/base/text-area';
import { Exercise } from './exercise';

export class WorkoutExerciseField extends FieldDef {
  static displayName = 'Workout Exercise';
  @field exercise = linksTo(Exercise);
  @field sets = contains(NumberField);
  @field reps = contains(NumberField);
  @field weight = contains(NumberField);
  @field notes = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='workout-exercise'>
        <div class='exercise-name'>{{@model.exercise.name}}</div>
        <div class='exercise-stats'>
          <span>{{@model.sets}} sets</span>
          <span>{{@model.reps}} reps</span>
          {{#if @model.weight}}<span>{{@model.weight}} kg</span>{{/if}}
        </div>
        {{#if @model.notes}}<div class='notes'>{{@model.notes}}</div>{{/if}}
      </div>
      <style scoped>
        .workout-exercise { padding: 0.5rem 0; border-bottom: 1px solid #eee; }
        .exercise-name { font-weight: bold; margin-bottom: 0.25rem; }
        .exercise-stats { display: flex; gap: 1rem; color: #555; font-size: 0.9rem; }
        .notes { color: #888; font-size: 0.85rem; margin-top: 0.25rem; }
      </style>
    </template>
  };
}

export class WorkoutSession extends CardDef {
  static displayName = 'Workout Session';
  @field title = contains(StringField);
  @field date = contains(DateField);
  @field durationMinutes = contains(NumberField);
  @field exercises = containsMany(WorkoutExerciseField);
  @field overallNotes = contains(TextAreaField);
  @field rating = contains(NumberField);

  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <div class='session-card'>
        <div class='session-header'>
          <h1>{{@model.title}}</h1>
          <div class='session-meta'>
            <span class='date'>{{@model.date}}</span>
            {{#if @model.durationMinutes}}
              <span class='duration'>{{@model.durationMinutes}} min</span>
            {{/if}}
            {{#if @model.rating}}
              <span class='rating'>{{@model.rating}}/5</span>
            {{/if}}
          </div>
        </div>
        <div class='exercises-section'>
          <h2>Exercises</h2>
          {{#each @model.exercises as |ex|}}
            <div class='exercise-item'>
              <div class='exercise-name'>{{ex.exercise.name}}</div>
              <div class='exercise-detail'>
                <span>{{ex.sets}} sets x {{ex.reps}} reps</span>
                {{#if ex.weight}}<span> @ {{ex.weight}} kg</span>{{/if}}
              </div>
              {{#if ex.notes}}<div class='ex-notes'>{{ex.notes}}</div>{{/if}}
            </div>
          {{/each}}
        </div>
        {{#if @model.overallNotes}}
          <div class='notes-section'>
            <h2>Notes</h2>
            <p>{{@model.overallNotes}}</p>
          </div>
        {{/if}}
      </div>
      <style scoped>
        .session-card { padding: 2rem; font-family: sans-serif; max-width: 700px; }
        .session-header { margin-bottom: 1.5rem; }
        h1 { font-size: 1.8rem; color: #1a1a2e; margin-bottom: 0.5rem; }
        h2 { font-size: 1.2rem; color: #333; margin-bottom: 1rem; border-bottom: 2px solid #e74c3c; padding-bottom: 0.25rem; }
        .session-meta { display: flex; gap: 1.5rem; color: #555; }
        .exercises-section { margin-bottom: 1.5rem; }
        .exercise-item { padding: 0.75rem; background: #f9f9f9; border-radius: 8px; margin-bottom: 0.5rem; }
        .exercise-name { font-weight: bold; margin-bottom: 0.25rem; }
        .exercise-detail { color: #555; font-size: 0.9rem; }
        .ex-notes { color: #888; font-size: 0.85rem; margin-top: 0.25rem; font-style: italic; }
        .notes-section p { color: #555; line-height: 1.6; }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='session-embedded'>
        <div class='session-title'>{{@model.title}}</div>
        <div class='session-info'>
          <span>{{@model.date}}</span>
          {{#if @model.durationMinutes}}<span>{{@model.durationMinutes}} min</span>{{/if}}
          {{#if @model.rating}}<span>{{@model.rating}}/5</span>{{/if}}
        </div>
      </div>
      <style scoped>
        .session-embedded { padding: 0.75rem; }
        .session-title { font-weight: bold; margin-bottom: 0.25rem; }
        .session-info { display: flex; gap: 1rem; color: #888; font-size: 0.85rem; }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <div class='session-fitted'>
        <span class='title'>{{@model.title}}</span>
        <span class='date'>{{@model.date}}</span>
      </div>
      <style scoped>
        .session-fitted { padding: 0.5rem; display: flex; justify-content: space-between; align-items: center; }
        .title { font-weight: bold; }
        .date { color: #888; font-size: 0.85rem; }
      </style>
    </template>
  };
}
