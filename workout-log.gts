// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
import {
  CardDef,
  field,
  contains,
  linksToMany,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import { Exercise } from './exercise';
import { WorkoutSession } from './workout-session';

export class WorkoutLog extends CardDef {
  static displayName = 'Workout Log';
  @field logName = contains(StringField);
  @field sessions = linksToMany(() => WorkoutSession);
  @field exerciseLibrary = linksToMany(Exercise);

  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <div class='workout-log'>
        <header class='log-header'>
          <h1>{{if @model.logName @model.logName 'My Workout Log'}}</h1>
          <div class='stats-bar'>
            <div class='stat'>
              <span class='stat-value'>{{@model.sessions.length}}</span>
              <span class='stat-label'>Sessions</span>
            </div>
            <div class='stat'>
              <span class='stat-value'>{{@model.exerciseLibrary.length}}</span>
              <span class='stat-label'>Exercises</span>
            </div>
          </div>
        </header>

        <section class='section'>
          <h2>Recent Sessions</h2>
          {{#if @model.sessions.length}}
            <div class='sessions-list'>
              <@fields.sessions @format='embedded' />
            </div>
          {{else}}
            <p class='empty'>No sessions logged yet. Start your first workout!</p>
          {{/if}}
        </section>

        <section class='section'>
          <h2>Exercise Library</h2>
          {{#if @model.exerciseLibrary.length}}
            <div class='exercise-grid'>
              <@fields.exerciseLibrary @format='fitted' />
            </div>
          {{else}}
            <p class='empty'>No exercises added yet. Build your library!</p>
          {{/if}}
        </section>
      </div>
      <style scoped>
        .workout-log {
          padding: 2rem;
          font-family: sans-serif;
          max-width: 800px;
          height: 100%;
          overflow-y: auto;
          box-sizing: border-box;
        }
        .log-header {
          margin-bottom: 2rem;
        }
        h1 {
          font-size: 2rem;
          color: #1a1a2e;
          margin-bottom: 1rem;
        }
        h2 {
          font-size: 1.2rem;
          color: #333;
          margin-bottom: 1rem;
          border-bottom: 2px solid #e74c3c;
          padding-bottom: 0.25rem;
        }
        .stats-bar {
          display: flex;
          gap: 2rem;
        }
        .stat {
          display: flex;
          flex-direction: column;
          align-items: center;
          background: #f4f4f4;
          border-radius: 10px;
          padding: 0.75rem 1.5rem;
        }
        .stat-value {
          font-size: 1.8rem;
          font-weight: bold;
          color: #e74c3c;
        }
        .stat-label {
          font-size: 0.8rem;
          color: #888;
          text-transform: uppercase;
        }
        .section {
          margin-bottom: 2rem;
        }
        .sessions-list > .containsMany-field {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }
        .exercise-grid > .containsMany-field {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
          gap: 1rem;
        }
        .empty {
          color: #aaa;
          font-style: italic;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='log-embedded'>
        <span class='log-name'>{{if
            @model.logName
            @model.logName
            'My Workout Log'
          }}</span>
        <span class='log-count'>{{@model.sessions.length}} sessions</span>
      </div>
      <style scoped>
        .log-embedded {
          display: flex;
          justify-content: space-between;
          padding: 0.75rem;
        }
        .log-name {
          font-weight: bold;
        }
        .log-count {
          color: #888;
          font-size: 0.85rem;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <div class='log-fitted'>
        <span class='name'>{{if
            @model.logName
            @model.logName
            'My Workout Log'
          }}</span>
        <span class='count'>{{@model.sessions.length}} sessions</span>
      </div>
      <style scoped>
        .log-fitted {
          padding: 0.5rem;
          display: flex;
          justify-content: space-between;
          align-items: center;
        }
        .name {
          font-weight: bold;
        }
        .count {
          color: #888;
          font-size: 0.8rem;
        }
      </style>
    </template>
  };
}
