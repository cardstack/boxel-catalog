import {
  CardDef,
  FieldDef,
  field,
  contains,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import MusicIcon from '@cardstack/boxel-icons/music';
import { array, get } from '@ember/helper';

// Drum Kit Definition - stores sound parameters for each kit
export class DrumKitField extends FieldDef {
  static displayName = 'Drum Kit';
  static icon = MusicIcon;

  @field kitName = contains(StringField);
  @field kickParams = contains(StringField);
  @field snareParams = contains(StringField);
  @field hihatParams = contains(StringField);
  @field openhatParams = contains(StringField);
  @field clapParams = contains(StringField);
  @field crashParams = contains(StringField);

  get soundParams() {
    try {
      return {
        kick: JSON.parse(
          this.kickParams || '{"type": "808", "frequency": 60, "decay": 0.3}',
        ),
        snare: JSON.parse(
          this.snareParams || '{"type": "808", "frequency": 200, "decay": 0.1}',
        ),
        hihat: JSON.parse(
          this.hihatParams ||
            '{"type": "808", "frequency": 8000, "decay": 0.05}',
        ),
        openhat: JSON.parse(
          this.openhatParams ||
            '{"type": "808", "frequency": 6000, "decay": 0.3}',
        ),
        clap: JSON.parse(
          this.clapParams || '{"type": "808", "frequency": 2000, "decay": 0.1}',
        ),
        crash: JSON.parse(
          this.crashParams ||
            '{"type": "808", "frequency": 3000, "decay": 1.0}',
        ),
      };
    } catch (e) {
      console.error('Error parsing sound parameters:', e);
      return {
        kick: { type: '808', frequency: 60, decay: 0.3 },
        snare: { type: '808', frequency: 200, decay: 0.1 },
        hihat: { type: '808', frequency: 8000, decay: 0.05 },
        openhat: { type: '808', frequency: 6000, decay: 0.3 },
        clap: { type: '808', frequency: 2000, decay: 0.1 },
        crash: { type: '808', frequency: 3000, decay: 1.0 },
      };
    }
  }
}

// Drum Kit Card Definition - stores complete drum kits as cards
export class DrumKitCard extends CardDef {
  static displayName = 'Drum Kit';
  static icon = MusicIcon;

  @field kitName = contains(StringField);
  @field cardDescription = contains(StringField);
  @field category = contains(StringField);
  @field creator = contains(StringField);
  @field kit = contains(DrumKitField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: DrumKitCard) {
      try {
        return this.kitName ?? 'Untitled Kit';
      } catch (e) {
        console.error('DrumKitCard: Error computing title', e);
        return 'Untitled Kit';
      }
    },
  });
}

export class BeatPatternField extends FieldDef {
  static displayName = 'Beat Pattern';
  static icon = MusicIcon;

  @field name = contains(StringField);
  @field kick = contains(StringField);
  @field snare = contains(StringField);
  @field hihat = contains(StringField);
  @field openhat = contains(StringField);
  @field clap = contains(StringField);
  @field crash = contains(StringField);

  get patternData() {
    try {
      return {
        kick: JSON.parse(
          this.kick ||
            '[false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false]',
        ),
        snare: JSON.parse(
          this.snare ||
            '[false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false]',
        ),
        hihat: JSON.parse(
          this.hihat ||
            '[false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false]',
        ),
        openhat: JSON.parse(
          this.openhat ||
            '[false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false]',
        ),
        clap: JSON.parse(
          this.clap ||
            '[false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false]',
        ),
        crash: JSON.parse(
          this.crash ||
            '[false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false]',
        ),
      };
    } catch (e) {
      console.error('Error parsing pattern data:', e);
      return {
        kick: new Array(16).fill(false),
        snare: new Array(16).fill(false),
        hihat: new Array(16).fill(false),
        openhat: new Array(16).fill(false),
        clap: new Array(16).fill(false),
        crash: new Array(16).fill(false),
      };
    }
  }

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='beat-pattern-field'>
        <div class='pattern-name'>{{if
            @model.name
            @model.name
            'Unnamed Pattern'
          }}</div>
        <div class='pattern-tracks'>
          <div class='track track-kick'>
            {{#each (array 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15) as |i|}}
              <div
                class='dot {{if (get @model.patternData.kick i) "on" ""}}'
              ></div>
            {{/each}}
          </div>
          <div class='track track-snare'>
            {{#each (array 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15) as |i|}}
              <div
                class='dot {{if (get @model.patternData.snare i) "on" ""}}'
              ></div>
            {{/each}}
          </div>
          <div class='track track-hihat'>
            {{#each (array 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15) as |i|}}
              <div
                class='dot {{if (get @model.patternData.hihat i) "on" ""}}'
              ></div>
            {{/each}}
          </div>
        </div>
      </div>

      <style scoped>
        .beat-pattern-field {
          padding: 0.5rem 0.625rem;
          background: rgba(255, 255, 255, 0.03);
          border: 1px solid rgba(255, 255, 255, 0.07);
          border-radius: var(--radius-sm, var(--boxel-border-radius-sm));
        }

        .pattern-name {
          font-size: 0.5625rem;
          font-weight: 700;
          color: rgba(255, 255, 255, 0.4);
          text-transform: uppercase;
          letter-spacing: 0.1em;
          margin-bottom: 0.375rem;
          font-family: var(--font-mono, monospace);
        }

        .pattern-tracks {
          display: flex;
          flex-direction: column;
          gap: 2px;
        }

        .track {
          display: flex;
          gap: 1px;
        }

        .dot {
          width: 7px;
          height: 5px;
          border-radius: 1px;
          background: rgba(255, 255, 255, 0.08);
          transition: all 0.1s ease;
        }

        .track-kick .dot.on {
          background: #ef4444;
          box-shadow: 0 0 4px rgba(239, 68, 68, 0.6);
        }

        .track-snare .dot.on {
          background: #3b82f6;
          box-shadow: 0 0 4px rgba(59, 130, 246, 0.6);
        }

        .track-hihat .dot.on {
          background: #10b981;
          box-shadow: 0 0 4px rgba(16, 185, 129, 0.6);
        }
      </style>
    </template>
  };
}

export class BeatPatternCard extends CardDef {
  static displayName = 'Beat Pattern';
  static icon = MusicIcon;

  @field patternName = contains(StringField);
  @field cardDescription = contains(StringField);
  @field bpm = contains(NumberField);
  @field genre = contains(StringField);
  @field creator = contains(StringField);
  @field pattern = contains(BeatPatternField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: BeatPatternCard) {
      try {
        return this.patternName ?? 'Untitled Beat';
      } catch (e) {
        console.error('BeatPatternCard: Error computing title', e);
        return 'Untitled Beat';
      }
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='beat-pattern-card'>
        <div class='pattern-header'>
          <h3 class='pattern-title'>{{if
              @model.patternName
              @model.patternName
              'Untitled Beat'
            }}</h3>
          <div class='pattern-tags'>
            {{#if @model.genre}}
              <span class='genre-tag'>{{@model.genre}}</span>
            {{/if}}
            {{#if @model.bpm}}
              <span class='bpm-tag'>{{@model.bpm}} BPM</span>
            {{/if}}
          </div>
        </div>

        {{#if @model.cardDescription}}
          <p class='pattern-desc'>{{@model.cardDescription}}</p>
        {{/if}}

        {{#if @fields.pattern}}
          <div class='pattern-preview'>
            <@fields.pattern @format='embedded' />
          </div>
        {{/if}}

        {{#if @model.creator}}
          <div class='pattern-footer'>
            <span class='creator'>by {{@model.creator}}</span>
          </div>
        {{/if}}
      </div>

      <style scoped>
        .beat-pattern-card {
          background: linear-gradient(135deg, #0a0d14 0%, #111827 100%);
          border-radius: var(--radius-xl, var(--boxel-border-radius-xl));
          padding: 0.875rem;
          color: #e2e8f0;
          border: 1px solid rgba(59, 130, 246, 0.15);
          transition: all 0.2s ease;
          font-family: var(--font-mono, monospace);
        }

        .beat-pattern-card:hover {
          border-color: rgba(59, 130, 246, 0.4);
          box-shadow: 0 0 20px rgba(59, 130, 246, 0.1);
        }

        .pattern-header {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          margin-bottom: 0.5rem;
        }

        .pattern-title {
          font-size: 0.875rem;
          font-weight: 700;
          margin: 0;
          background: linear-gradient(135deg, #60a5fa, #a78bfa);
          -webkit-background-clip: text;
          -webkit-text-fill-color: transparent;
          background-clip: text;
        }

        .pattern-tags {
          display: flex;
          gap: 0.25rem;
          align-items: center;
          flex-shrink: 0;
        }

        .genre-tag {
          background: rgba(255, 255, 255, 0.08);
          color: rgba(255, 255, 255, 0.5);
          padding: 0.125rem 0.375rem;
          border-radius: 99px;
          font-size: 0.5rem;
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.08em;
        }

        .bpm-tag {
          background: rgba(34, 211, 238, 0.12);
          color: #22d3ee;
          padding: 0.125rem 0.375rem;
          border-radius: 99px;
          font-size: 0.5rem;
          font-weight: 700;
          letter-spacing: 0.05em;
        }

        .pattern-desc {
          font-size: 0.6875rem;
          color: rgba(255, 255, 255, 0.4);
          margin: 0 0 0.5rem 0;
          line-height: 1.5;
        }

        .pattern-preview {
          margin-bottom: 0.5rem;
        }

        .pattern-footer {
          padding-top: 0.375rem;
          border-top: 1px solid rgba(255, 255, 255, 0.06);
        }

        .creator {
          font-size: 0.5625rem;
          color: rgba(255, 255, 255, 0.3);
          font-style: italic;
        }
      </style>
    </template>
  };
}
