import { fn } from '@ember/helper';
// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
import {
  CardDef,
  FieldDef,
  field,
  contains,
  linksTo,
  Component,
} from 'https://cardstack.com/base/card-api'; // ¹ Core imports
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import BooleanField from 'https://cardstack.com/base/boolean';
import { Button } from '@cardstack/boxel-ui/components'; // ² UI components
import { on } from '@ember/modifier';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { task, timeout } from 'ember-concurrency'; // ³ Async task handling
import MapIcon from '@cardstack/boxel-icons/map'; // ⁴ Icon import
import { RacingGame } from './racing-game';

// ⁵ Track data field for storing track layout
export class TrackData extends FieldDef {
  static displayName = 'Track Data';

  @field trackName = contains(StringField);
  @field trackType = contains(StringField); // 'oval', 'circuit', 'street'
  @field innerRadius = contains(NumberField);
  @field outerRadius = contains(NumberField);
  @field startX = contains(NumberField);
  @field startZ = contains(NumberField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='track-data'>
        <span class='track-name'>{{@model.trackName}}</span>
        <span class='track-type'>{{@model.trackType}}</span>
      </div>

      <style scoped>
        .track-data {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
          font-size: 0.75rem;
        }

        .track-name {
          font-weight: 600;
          color: #111827;
        }

        .track-type {
          color: #6b7280;
          text-transform: capitalize;
        }
      </style>
    </template>
  };
}

export class RaceMap extends CardDef {
  // ⁶ Main map card definition
  static displayName = 'Race Map';
  static icon = MapIcon;

  @field cardTitle = contains(StringField, {
    computeVia: function (this: RaceMap) {
      return this.mapName ?? 'Race Map';
    },
  });

  @field mapName = contains(StringField); // ⁷ Primary fields
  @field cardDescription = contains(StringField);
  @field isActive = contains(BooleanField);
  @field trackData = contains(TrackData);
  @field racingGame = linksTo(() => RacingGame); // ⁸ Link to racing game

  static isolated = class Isolated extends Component<typeof this> {
    // ⁹ Main map component - designed for side panel
    @tracked carPosition = { x: 20, y: 0, z: 0 }; // ¹⁰ Car tracking
    @tracked carRotation = 0;
    @tracked isTracking = false;
    @tracked raceStarted = false;

    // ¹¹ Map dimensions and scaling
    mapWidth = 400;
    mapHeight = 400;
    mapScale = 10; // Scale factor for converting 3D coords to 2D map

    // ¹² Start tracking the racing game
    startTracking = task(async () => {
      this.isTracking = true;
      this.raceStarted = true;
      this.args.model.isActive = true;

      // ¹³ Start race button - open racing game in right panel
      if (this.args.context?.actions?.viewCard && this.args.model.racingGame) {
        // Open the racing game in the rightmost stack (side-by-side)
        this.args.context.actions.viewCard(
          this.args.model.racingGame,
          'isolated',
          {
            openCardInRightMostStack: true,
          },
        );
      }

      // ¹⁴ Simulate car position updates (in real implementation, this would sync with the racing game)
      this.trackCarPosition();
    });

    // ¹⁵ Simulate car tracking (in production, this would communicate with the racing game)
    trackCarPosition = task(async () => {
      let angle = 0;
      const radius = 20;

      while (this.isTracking) {
        // ¹⁶ Simulate car moving around oval track
        this.carPosition = {
          x: Math.cos(angle) * radius,
          y: 0,
          z: Math.sin(angle) * radius,
        };
        this.carRotation = angle + Math.PI / 2;

        angle += 0.02; // Speed of simulation
        if (angle > Math.PI * 2) angle = 0;

        await timeout(50); // 20 FPS update rate
      }
    });

    @action // ¹⁷ UI actions
    stopTracking() {
      this.isTracking = false;
      this.raceStarted = false;
      this.args.model.isActive = false;
    }

    @action
    resetMap() {
      this.carPosition = { x: 20, y: 0, z: 0 };
      this.carRotation = 0;
      this.stopTracking();
    }

    // ¹⁸ Convert 3D coordinates to 2D map coordinates
    get carMapPosition() {
      const centerX = this.mapWidth / 2;
      const centerY = this.mapHeight / 2;

      return {
        x: centerX + this.carPosition.x * this.mapScale,
        y: centerY + this.carPosition.z * this.mapScale,
      };
    }

    <template>
      <div class='stage'>
        <div class='race-map-mat'>
          <!-- ¹⁹ Map header -->
          <header class='map-header'>
            <h1>{{if @model.mapName @model.mapName 'Race Map'}}</h1>
            {{#if @model.cardDescription}}
              <p class='map-description'>{{@model.cardDescription}}</p>
            {{/if}}
          </header>

          <!-- ²⁰ Race controls -->
          <section class='race-controls'>
            {{#if this.raceStarted}}
              <Button class='stop-btn' {{on 'click' this.stopTracking}}>
                <svg
                  class='control-icon'
                  viewBox='0 0 24 24'
                  fill='currentColor'
                >
                  <rect x='6' y='4' width='4' height='16' />
                  <rect x='14' y='4' width='4' height='16' />
                </svg>
                Stop Race
              </Button>
              <Button class='reset-btn' {{on 'click' this.resetMap}}>
                <svg
                  class='control-icon'
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2'
                >
                  <polyline points='23 4 23 10 17 10' />
                  <path d='M20.49 15a9 9 0 1 1-2.12-9.36L23 10' />
                </svg>
                Reset
              </Button>
            {{else}}
              <Button
                class='start-btn'
                @disabled={{this.startTracking.isRunning}}
                {{on 'click' (fn this.startTracking.perform)}}
              >
                {{#if this.startTracking.isRunning}}
                  <svg class='spinner control-icon' viewBox='0 0 24 24'>
                    <circle
                      cx='12'
                      cy='12'
                      r='10'
                      fill='none'
                      stroke='currentColor'
                      stroke-width='2'
                      opacity='0.25'
                    />
                    <path
                      fill='currentColor'
                      d='M4 12a8 8 0 0 1 8-8v2a6 6 0 0 0-6 6z'
                      opacity='0.75'
                    />
                  </svg>
                  Starting...
                {{else}}
                  <svg
                    class='control-icon'
                    viewBox='0 0 24 24'
                    fill='currentColor'
                  >
                    <polygon points='5,3 19,12 5,21' />
                  </svg>
                  Start Race
                {{/if}}
              </Button>
            {{/if}}
          </section>

          <!-- ²¹ Track map visualization -->
          <section class='map-section'>
            <div
              class='track-map'
              style='width: {{this.mapWidth}}px; height: {{this.mapHeight}}px;'
            >
              <!-- ²² Track layout (oval) -->
              <div class='track-outer-boundary'></div>
              <div class='track-surface'></div>
              <div class='track-inner-boundary'></div>

              <!-- ²³ Start/finish line -->
              <div class='start-finish-line'></div>

              <!-- ²⁴ Car indicator -->
              {{#if this.isTracking}}
                <div
                  class='car-indicator'
                  style='transform: translate({{this.carMapPosition.x}}px, {{this.carMapPosition.y}}px) rotate({{this.carRotation}}rad) translate(-50%, -50%);'
                >
                  <div class='car-body'></div>
                  <div class='car-direction'></div>
                </div>
              {{/if}}
            </div>
          </section>

          <!-- ²⁵ Map info -->
          {{#if @model.trackData}}
            <section class='track-info'>
              <h3>Track Information</h3>
              <@fields.trackData />
            </section>
          {{/if}}

          <!-- ²⁶ Race status -->
          <section class='race-status'>
            <div class='status-item'>
              <span class='label'>Status:</span>
              <span class='value {{if this.raceStarted "active" "inactive"}}'>
                {{if this.raceStarted 'Race Active' 'Ready to Race'}}
              </span>
            </div>
            {{#if this.isTracking}}
              <div class='status-item'>
                <span class='label'>Position:</span>
                <span class='value'>X:
                  {{this.carPosition.x}}
                  Z:
                  {{this.carPosition.z}}</span>
              </div>
            {{/if}}
          </section>
        </div>
      </div>

      <style scoped>
        /* ²⁷ Race map styles - optimized for side panel */
        .stage {
          width: 100%;
          height: 100%;
          display: flex;
          justify-content: center;
          padding: 1rem;
          background: linear-gradient(135deg, #1f2937 0%, #374151 100%);
          font-family:
            'Inter',
            -apple-system,
            sans-serif;
        }

        .race-map-mat {
          max-width: 28rem;
          width: 100%;
          overflow-y: auto;
          max-height: 100%;
        }

        .map-header {
          text-align: center;
          margin-bottom: 1.5rem;
        }

        .map-header h1 {
          font-size: 1.75rem;
          font-weight: 700;
          color: white;
          margin-bottom: 0.5rem;
          text-shadow: 0 2px 4px rgba(0, 0, 0, 0.3);
        }

        .map-description {
          color: rgba(255, 255, 255, 0.8);
          font-size: 0.875rem;
          line-height: 1.5;
        }

        /* ²⁸ Race controls */
        .race-controls {
          display: flex;
          gap: 0.75rem;
          justify-content: center;
          margin-bottom: 1.5rem;
        }

        .start-btn {
          background: linear-gradient(135deg, #10b981 0%, #059669 100%);
          color: white;
          border: none;
          padding: 0.75rem 1.5rem;
          border-radius: 0.5rem;
          font-weight: 600;
          display: flex;
          align-items: center;
          gap: 0.5rem;
          cursor: pointer;
          transition: all 0.2s ease;
        }

        .start-btn:hover:not(:disabled) {
          transform: translateY(-1px);
          box-shadow: 0 4px 12px rgba(16, 185, 129, 0.4);
        }

        .start-btn:disabled {
          opacity: 0.6;
          cursor: not-allowed;
        }

        .stop-btn {
          background: #ef4444;
          color: white;
          border: none;
          padding: 0.5rem 1rem;
          border-radius: 0.375rem;
          font-weight: 600;
          display: flex;
          align-items: center;
          gap: 0.375rem;
          cursor: pointer;
          transition: all 0.2s ease;
        }

        .stop-btn:hover {
          background: #dc2626;
        }

        .reset-btn {
          background: #6b7280;
          color: white;
          border: none;
          padding: 0.5rem 1rem;
          border-radius: 0.375rem;
          font-weight: 600;
          display: flex;
          align-items: center;
          gap: 0.375rem;
          cursor: pointer;
          transition: all 0.2s ease;
        }

        .reset-btn:hover {
          background: #4b5563;
        }

        .control-icon {
          width: 1rem;
          height: 1rem;
        }

        .spinner {
          animation: spin 1s linear infinite;
        }

        @keyframes spin {
          from {
            transform: rotate(0deg);
          }
          to {
            transform: rotate(360deg);
          }
        }

        /* ²⁹ Track map */
        .map-section {
          display: flex;
          justify-content: center;
          margin-bottom: 1.5rem;
        }

        .track-map {
          position: relative;
          background: #065f46;
          border: 3px solid #047857;
          border-radius: 1rem;
          overflow: hidden;
          box-shadow: 0 8px 24px rgba(0, 0, 0, 0.3);
        }

        /* ³⁰ Track elements */
        .track-outer-boundary {
          position: absolute;
          top: 50%;
          left: 50%;
          width: 360px;
          height: 360px;
          border: 4px solid #dc2626;
          border-radius: 50%;
          transform: translate(-50%, -50%);
        }

        .track-surface {
          position: absolute;
          top: 50%;
          left: 50%;
          width: 300px;
          height: 300px;
          background: #374151;
          border-radius: 50%;
          transform: translate(-50%, -50%);
          border: 2px solid #6b7280;
        }

        .track-inner-boundary {
          position: absolute;
          top: 50%;
          left: 50%;
          width: 180px;
          height: 180px;
          border: 4px solid #dc2626;
          border-radius: 50%;
          transform: translate(-50%, -50%);
        }

        .start-finish-line {
          position: absolute;
          top: 50%;
          right: 20px;
          width: 6px;
          height: 80px;
          background: repeating-linear-gradient(
            0deg,
            white 0px,
            white 8px,
            black 8px,
            black 16px
          );
          transform: translateY(-50%);
          border-radius: 3px;
        }

        /* ³¹ Car indicator */
        .car-indicator {
          position: absolute;
          z-index: 10;
          pointer-events: none;
          transition: transform 0.1s ease-out;
        }

        .car-body {
          width: 12px;
          height: 20px;
          background: #ef4444;
          border-radius: 3px;
          border: 2px solid white;
          box-shadow: 0 2px 4px rgba(0, 0, 0, 0.3);
        }

        .car-direction {
          position: absolute;
          top: -3px;
          left: 50%;
          width: 0;
          height: 0;
          border-left: 4px solid transparent;
          border-right: 4px solid transparent;
          border-bottom: 8px solid #fbbf24;
          transform: translateX(-50%);
        }

        /* ³² Info sections */
        .track-info,
        .race-status {
          background: rgba(255, 255, 255, 0.1);
          backdrop-filter: blur(10px);
          border-radius: 0.75rem;
          padding: 1rem;
          margin-bottom: 1rem;
          border: 1px solid rgba(255, 255, 255, 0.2);
        }

        .track-info h3 {
          font-size: 1rem;
          font-weight: 600;
          color: white;
          margin-bottom: 0.75rem;
        }

        .race-status {
          margin-bottom: 0;
        }

        .status-item {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 0.5rem;
        }

        .status-item:last-child {
          margin-bottom: 0;
        }

        .status-item .label {
          color: rgba(255, 255, 255, 0.8);
          font-size: 0.875rem;
          font-weight: 500;
        }

        .status-item .value {
          font-size: 0.875rem;
          font-weight: 600;
          font-family: 'SF Mono', Monaco, monospace;
        }

        .value.active {
          color: #10b981;
        }

        .value.inactive {
          color: #fbbf24;
        }

        /* ³³ Responsive design */
        @media (max-width: 640px) {
          .stage {
            padding: 0.5rem;
          }

          .track-map {
            width: 300px !important;
            height: 300px !important;
          }

          .track-outer-boundary {
            width: 260px;
            height: 260px;
          }

          .track-surface {
            width: 200px;
            height: 200px;
          }

          .track-inner-boundary {
            width: 120px;
            height: 120px;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    // ³⁴ Embedded format for previews
    <template>
      <div class='map-card'>
        <header>
          <h3>{{if @model.mapName @model.mapName 'Race Map'}}</h3>
          {{#if @model.cardDescription}}
            <p class='card-description'>{{@model.cardDescription}}</p>
          {{/if}}
        </header>

        <div class='mini-map'>
          <div class='mini-track'></div>
          <div class='mini-car'></div>
        </div>

        <div class='map-status'>
          {{#if @model.isActive}}
            <span class='status active'>Tracking Active</span>
          {{else}}
            <span class='status inactive'>Ready to Track</span>
          {{/if}}
        </div>
      </div>

      <style scoped>
        .map-card {
          border: 1px solid #e5e7eb;
          border-radius: 0.75rem;
          padding: 1rem;
          background: white;
        }

        .map-card header h3 {
          font-size: 1.125rem;
          font-weight: 600;
          color: #111827;
          margin-bottom: 0.25rem;
        }

        .card-description {
          font-size: 0.875rem;
          color: #6b7280;
          line-height: 1.4;
          margin-bottom: 1rem;
        }

        .mini-map {
          position: relative;
          width: 100px;
          height: 100px;
          margin: 0 auto 1rem;
          background: #065f46;
          border-radius: 50%;
          border: 2px solid #047857;
        }

        .mini-track {
          position: absolute;
          top: 50%;
          left: 50%;
          width: 60px;
          height: 60px;
          border: 2px solid #374151;
          border-radius: 50%;
          transform: translate(-50%, -50%);
        }

        .mini-car {
          position: absolute;
          top: 20%;
          right: 20%;
          width: 6px;
          height: 8px;
          background: #ef4444;
          border-radius: 1px;
          transform: rotate(45deg);
        }

        .map-status {
          text-align: center;
        }

        .status {
          font-size: 0.875rem;
          font-weight: 600;
        }

        .status.active {
          color: #10b981;
        }

        .status.inactive {
          color: #f59e0b;
        }
      </style>
    </template>
  };
}
