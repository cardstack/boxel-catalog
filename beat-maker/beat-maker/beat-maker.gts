import {
  CardDef,
  FieldDef,
  field,
  contains,
  linksTo,
  linksToMany,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import MusicIcon from '@cardstack/boxel-icons/music';
import { Button } from '@cardstack/boxel-ui/components';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { fn, get, array, concat } from '@ember/helper';
import { eq, gt, or } from '@cardstack/boxel-ui/helpers';

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

class BeatMakerIsolated extends Component<typeof BeatMakerCard> {
  @tracked isPlaying = false;
  @tracked currentStep = 0;
  @tracked volumes = {
    kick: 85,
    snare: 75,
    hihat: 60,
    openhat: 50,
    clap: 70,
    crash: 40,
  };

  get bpm() {
    return this.args.model?.bpm || 120;
  }

  get swing() {
    return this.args.model?.swing || 0;
  }

  get masterVolume() {
    return this.args.model?.masterVolume || 75;
  }

  get selectedKit() {
    return (
      this.args.model?.currentKit?.kitName ||
      this.args.model?.instrumentKit ||
      '808 Analog'
    );
  }

  getInstrumentVolume = (instrument: string): number => {
    return (this.volumes as any)[instrument] || 0;
  };

  get currentKitParams() {
    try {
      const kit = this.args.model?.currentKit?.kit;
      if (kit) {
        return {
          kick: JSON.parse(
            kit.kickParams || '{"type": "808", "frequency": 60, "decay": 0.3}',
          ),
          snare: JSON.parse(
            kit.snareParams ||
              '{"type": "808", "frequency": 200, "decay": 0.1}',
          ),
          hihat: JSON.parse(
            kit.hihatParams ||
              '{"type": "808", "frequency": 8000, "decay": 0.05}',
          ),
          openhat: JSON.parse(
            kit.openhatParams ||
              '{"type": "808", "frequency": 6000, "decay": 0.3}',
          ),
          clap: JSON.parse(
            kit.clapParams ||
              '{"type": "808", "frequency": 2000, "decay": 0.1}',
          ),
          crash: JSON.parse(
            kit.crashParams ||
              '{"type": "808", "frequency": 3000, "decay": 1.0}',
          ),
        };
      }
      return {
        kick: { type: '808', frequency: 60, decay: 0.3 },
        snare: { type: '808', frequency: 200, decay: 0.1 },
        hihat: { type: '808', frequency: 8000, decay: 0.05 },
        openhat: { type: '808', frequency: 6000, decay: 0.3 },
        clap: { type: '808', frequency: 2000, decay: 0.1 },
        crash: { type: '808', frequency: 3000, decay: 1.0 },
      };
    } catch (e) {
      console.error('Error accessing kit parameters:', e);
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

  get availableKits() {
    try {
      if (
        this.args.model?.availableKits &&
        this.args.model.availableKits.length > 0
      ) {
        return this.args.model.availableKits;
      }
      return [];
    } catch (e) {
      console.error('Error accessing available kits:', e);
      return [];
    }
  }

  get availablePatterns() {
    try {
      if (
        this.args.model?.availablePatterns &&
        this.args.model.availablePatterns.length > 0
      ) {
        return this.args.model.availablePatterns;
      }
      return [];
    } catch (e) {
      console.error('Error accessing available patterns:', e);
      return [];
    }
  }

  get patterns() {
    try {
      if (this.args.model?.currentPattern?.pattern?.patternData) {
        return this.args.model.currentPattern.pattern.patternData;
      }
      return {
        kick: [
          true,
          false,
          false,
          false,
          true,
          false,
          false,
          false,
          true,
          false,
          false,
          false,
          true,
          false,
          false,
          false,
        ],
        snare: [
          false,
          false,
          false,
          false,
          true,
          false,
          false,
          false,
          false,
          false,
          false,
          false,
          true,
          false,
          false,
          false,
        ],
        hihat: [
          true,
          true,
          true,
          true,
          true,
          true,
          true,
          true,
          true,
          true,
          true,
          true,
          true,
          true,
          true,
          true,
        ],
        openhat: [
          false,
          false,
          false,
          true,
          false,
          false,
          false,
          true,
          false,
          false,
          false,
          true,
          false,
          false,
          false,
          false,
        ],
        clap: [
          false,
          false,
          false,
          false,
          false,
          false,
          false,
          false,
          false,
          false,
          false,
          false,
          false,
          false,
          false,
          false,
        ],
        crash: [
          true,
          false,
          false,
          false,
          false,
          false,
          false,
          false,
          false,
          false,
          false,
          false,
          false,
          false,
          false,
          false,
        ],
      };
    } catch (e) {
      console.error('Error getting patterns:', e);
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

  get visualCurrentStep() {
    return this.currentStep === 0 ? 15 : this.currentStep - 1;
  }

  get stepStates() {
    try {
      const patterns = this.patterns;
      const states: { [key: string]: boolean } = {};
      Object.keys(patterns).forEach((instrument) => {
        const instrumentPattern = patterns[instrument as keyof typeof patterns];
        if (instrumentPattern) {
          for (let step = 0; step < 16; step++) {
            states[`${instrument}-${step}`] = instrumentPattern[step] || false;
          }
        }
      });
      return states;
    } catch (e) {
      console.error('Error creating step states:', e);
      return {};
    }
  }

  updatePatterns(newPatterns: any) {
    try {
      if (this.args.model?.currentPattern?.pattern) {
        this.args.model.currentPattern.pattern.kick = JSON.stringify(
          newPatterns.kick,
        );
        this.args.model.currentPattern.pattern.snare = JSON.stringify(
          newPatterns.snare,
        );
        this.args.model.currentPattern.pattern.hihat = JSON.stringify(
          newPatterns.hihat,
        );
        this.args.model.currentPattern.pattern.openhat = JSON.stringify(
          newPatterns.openhat,
        );
        this.args.model.currentPattern.pattern.clap = JSON.stringify(
          newPatterns.clap,
        );
        this.args.model.currentPattern.pattern.crash = JSON.stringify(
          newPatterns.crash,
        );
      }
    } catch (e) {
      console.error('Error updating patterns:', e);
    }
  }

  audioContext: AudioContext | null = null;
  sequenceTimer: number | null = null;
  nextStepTime = 0;
  lookahead = 25.0;
  scheduleAheadTime = 0.1;

  constructor(owner: any, args: any) {
    super(owner, args);
    this.initializeAudio();
  }

  initializeAudio() {
    try {
      this.audioContext = new (
        window.AudioContext || (window as any).webkitAudioContext
      )();
    } catch (e) {
      console.warn('Web Audio API not supported');
    }
  }

  willDestroy(): void {
    this.stop();
    if (this.audioContext) {
      this.audioContext.close().catch(() => undefined);
    }
    this.audioContext = null;
  }

  playKick(time: number, volume: number) {
    if (!this.audioContext) return;
    const kickParams = this.currentKitParams.kick;
    this.playDynamicKick(time, volume, kickParams);
  }

  playDynamicKick(time: number, volume: number, params: any) {
    const osc = this.audioContext!.createOscillator();
    const gain = this.audioContext!.createGain();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(params.frequency || 60, time);
    osc.frequency.exponentialRampToValueAtTime(
      (params.frequency || 60) * 0.5,
      time + 0.05,
    );
    osc.frequency.exponentialRampToValueAtTime(
      0.01,
      time + (params.decay || 0.3),
    );
    gain.gain.setValueAtTime(0, time);
    gain.gain.linearRampToValueAtTime(
      volume * (params.amplitude || 1.0),
      time + 0.01,
    );
    gain.gain.exponentialRampToValueAtTime(0.01, time + (params.decay || 0.3));
    osc.connect(gain);
    gain.connect(this.audioContext!.destination);
    osc.start(time);
    osc.stop(time + (params.decay || 0.3));
  }

  playSnare(time: number, volume: number) {
    if (!this.audioContext) return;
    const snareParams = this.currentKitParams.snare;
    this.playDynamicSnare(time, volume, snareParams);
  }

  playHihat(time: number, volume: number) {
    if (!this.audioContext) return;
    const hihatParams = this.currentKitParams.hihat;
    this.playDynamicHihat(time, volume, hihatParams);
  }

  playOpenhat(time: number, volume: number) {
    if (!this.audioContext) return;
    const openhatParams = this.currentKitParams.openhat;
    this.playDynamicHihat(time, volume, openhatParams);
  }

  playClap(time: number, volume: number) {
    if (!this.audioContext) return;
    const clapParams = this.currentKitParams.clap;
    this.playDynamicSnare(time, volume, clapParams);
  }

  playCrash(time: number, volume: number) {
    if (!this.audioContext) return;
    const crashParams = this.currentKitParams.crash;
    this.playDynamicHihat(time, volume, crashParams);
  }

  playDynamicSnare(time: number, volume: number, params: any) {
    const noise = this.audioContext!.createBufferSource();
    const gain = this.audioContext!.createGain();
    const filter = this.audioContext!.createBiquadFilter();
    const bufferSize = this.audioContext!.sampleRate * (params.decay || 0.1);
    const buffer = this.audioContext!.createBuffer(
      1,
      bufferSize,
      this.audioContext!.sampleRate,
    );
    const output = buffer.getChannelData(0);
    for (let i = 0; i < bufferSize; i++) {
      output[i] =
        (Math.random() * 2 - 1) *
        Math.pow(1 - i / bufferSize, params.shape || 2);
    }
    noise.buffer = buffer;
    filter.type = 'highpass';
    filter.frequency.value = params.frequency || 200;
    filter.Q.value = params.resonance || 5;
    gain.gain.setValueAtTime(volume * (params.amplitude || 0.8), time);
    gain.gain.exponentialRampToValueAtTime(0.01, time + (params.decay || 0.1));
    noise.connect(filter);
    filter.connect(gain);
    gain.connect(this.audioContext!.destination);
    noise.start(time);
    noise.stop(time + (params.decay || 0.1));
  }

  playDynamicHihat(time: number, volume: number, params: any) {
    const noise = this.audioContext!.createBufferSource();
    const gain = this.audioContext!.createGain();
    const filter = this.audioContext!.createBiquadFilter();
    const bufferSize = this.audioContext!.sampleRate * (params.decay || 0.05);
    const buffer = this.audioContext!.createBuffer(
      1,
      bufferSize,
      this.audioContext!.sampleRate,
    );
    const output = buffer.getChannelData(0);
    for (let i = 0; i < bufferSize; i++) {
      output[i] =
        (Math.random() * 2 - 1) *
        Math.pow(1 - i / bufferSize, params.shape || 4);
    }
    noise.buffer = buffer;
    filter.type = 'highpass';
    filter.frequency.value = params.frequency || 8000;
    filter.Q.value = params.resonance || 2;
    gain.gain.setValueAtTime(volume * (params.amplitude || 0.6), time);
    gain.gain.exponentialRampToValueAtTime(0.01, time + (params.decay || 0.05));
    noise.connect(filter);
    filter.connect(gain);
    gain.connect(this.audioContext!.destination);
    noise.start(time);
    noise.stop(time + (params.decay || 0.05));
  }

  scheduler() {
    while (
      this.nextStepTime <
      this.audioContext!.currentTime + this.scheduleAheadTime
    ) {
      this.scheduleStep(this.currentStep, this.nextStepTime);
      this.nextStep();
    }
  }

  scheduleStep(stepNumber: number, time: number) {
    const masterVol = (this.masterVolume / 100) * 0.3;
    Object.keys(this.patterns).forEach((instrument) => {
      if (this.patterns[instrument as keyof typeof this.patterns][stepNumber]) {
        const volume =
          (this.volumes[instrument as keyof typeof this.volumes] / 100) *
          masterVol;
        switch (instrument) {
          case 'kick':
            this.playKick(time, volume);
            break;
          case 'snare':
            this.playSnare(time, volume);
            break;
          case 'hihat':
            this.playHihat(time, volume);
            break;
          case 'openhat':
            this.playOpenhat(time, volume);
            break;
          case 'clap':
            this.playClap(time, volume);
            break;
          case 'crash':
            this.playCrash(time, volume);
            break;
        }
      }
    });
  }

  nextStep() {
    const baseStepLength = 60.0 / this.bpm / 4;
    const swingAmount = this.swing / 100;
    let stepLength = baseStepLength;
    if (this.currentStep % 2 === 1) {
      stepLength = baseStepLength * (1 + swingAmount * 0.67);
    } else if (this.currentStep % 2 === 0 && this.currentStep > 0) {
      stepLength = baseStepLength * (1 - swingAmount * 0.33);
    }
    this.nextStepTime += stepLength;
    this.currentStep = (this.currentStep + 1) % 16;
  }

  start() {
    if (!this.audioContext) {
      this.initializeAudio();
    }
    if (this.audioContext?.state === 'suspended') {
      this.audioContext.resume();
    }
    this.isPlaying = true;
    this.currentStep = 0;
    this.nextStepTime = this.audioContext!.currentTime;
    this.sequenceTimer = window.setInterval(
      () => this.scheduler(),
      this.lookahead,
    );
  }

  stop() {
    this.isPlaying = false;
    this.currentStep = 0;
    if (this.sequenceTimer) {
      clearInterval(this.sequenceTimer);
      this.sequenceTimer = null;
    }
  }

  @action
  togglePlay() {
    if (this.isPlaying) {
      this.stop();
    } else {
      this.start();
    }
  }

  @action
  toggleStep(instrument: string, step: number) {
    const currentPatterns = this.patterns;
    const newPatterns = { ...currentPatterns };
    newPatterns[instrument as keyof typeof newPatterns] = [
      ...newPatterns[instrument as keyof typeof newPatterns],
    ];
    newPatterns[instrument as keyof typeof newPatterns][step] =
      !newPatterns[instrument as keyof typeof newPatterns][step];
    this.updatePatterns(newPatterns);
  }

  @action
  clearPattern(instrument: string) {
    const currentPatterns = this.patterns;
    const newPatterns = { ...currentPatterns };
    newPatterns[instrument as keyof typeof newPatterns] = new Array(16).fill(
      false,
    );
    this.updatePatterns(newPatterns);
  }

  @action
  fillPattern(instrument: string) {
    const currentPatterns = this.patterns;
    const newPatterns = { ...currentPatterns };
    newPatterns[instrument as keyof typeof newPatterns] = new Array(16).fill(
      true,
    );
    this.updatePatterns(newPatterns);
  }

  @action
  loadPreset(patternCard: any) {
    if (this.args.model && patternCard) {
      this.args.model.currentPattern = patternCard;
      if (patternCard.bpm && this.args.model.bpm !== patternCard.bpm) {
        this.args.model.bpm = patternCard.bpm;
      }
    }
  }

  @action
  randomizePattern(instrument: string) {
    const currentPatterns = this.patterns;
    const newPatterns = { ...currentPatterns };
    newPatterns[instrument as keyof typeof newPatterns] = new Array(16)
      .fill(false)
      .map(() => Math.random() > 0.7);
    this.updatePatterns(newPatterns);
  }

  @action
  saveCurrentPattern() {
    console.log('Save current pattern functionality would be implemented here');
  }

  @action
  loadPatternCard(patternCard: any) {
    if (this.args.model) {
      this.args.model.currentPattern = patternCard;
      if (patternCard.bpm && this.args.model.bpm !== patternCard.bpm) {
        this.args.model.bpm = patternCard.bpm;
      }
    }
  }

  @action
  updateBpm(event: Event) {
    const target = event.target as HTMLInputElement;
    const value = parseInt(target.value);
    if (this.args.model) {
      this.args.model.bpm = value;
    }
  }

  @action
  updateSwing(event: Event) {
    const target = event.target as HTMLInputElement;
    const value = parseInt(target.value);
    if (this.args.model) {
      this.args.model.swing = value;
    }
  }

  @action
  updateMasterVolume(event: Event) {
    const target = event.target as HTMLInputElement;
    const value = parseInt(target.value);
    if (this.args.model) {
      this.args.model.masterVolume = value;
    }
  }

  @action
  updateVolume(instrument: string, event: Event) {
    const target = event.target as HTMLInputElement;
    this.volumes = { ...this.volumes, [instrument]: parseInt(target.value) };
  }

  @action
  handleKitSelection(event: Event) {
    const target = event.target as HTMLSelectElement;
    const selectedKitId = target.value;
    const selectedKit = this.availableKits.find(
      (kit) => kit.id === selectedKitId,
    );
    if (this.args.model && selectedKit) {
      this.args.model.currentKit = selectedKit;
      this.args.model.instrumentKit = selectedKit.kitName;
    }
  }

  @action
  selectKit(kitCard: any) {
    if (this.args.model && kitCard) {
      this.args.model.currentKit = kitCard;
      this.args.model.instrumentKit = kitCard.kitName;
    }
  }

  <template>
    <div class='studio'>

      {{! ═══ STUDIO HEADER ═══ }}
      <header class='studio-header'>
        {{! Row 1: Brand · LCD · Play }}
        <div class='header-top'>
          <div class='brand'>
            <div class='brand-icon'>
              <svg viewBox='0 0 24 24' fill='currentColor'>
                <circle cx='12' cy='12' r='9' opacity='0.2' />
                <circle cx='12' cy='12' r='6' opacity='0.5' />
                <circle cx='12' cy='12' r='3' />
                <line
                  x1='12'
                  y1='3'
                  x2='12'
                  y2='1'
                  stroke='currentColor'
                  stroke-width='2'
                  stroke-linecap='round'
                />
              </svg>
            </div>
            <div class='brand-text'>
              <div class='brand-name'>RHYTHM STUDIO</div>
              <div class='brand-sub'>16-STEP SEQUENCER</div>
            </div>
          </div>

          <div class='lcd-display'>
            <div class='lcd-row'>
              <span class='lcd-label'>BPM</span>
              <span class='lcd-val'>{{this.bpm}}</span>
            </div>
            <div class='lcd-divider'></div>
            <div class='lcd-row'>
              <span class='lcd-label'>SWG</span>
              <span class='lcd-val'>{{this.swing}}</span>
            </div>
            <div class='lcd-divider'></div>
            <div class='lcd-row'>
              <span class='lcd-label'>VOL</span>
              <span class='lcd-val'>{{this.masterVolume}}</span>
            </div>
          </div>

          <Button
            class='play-btn {{if this.isPlaying "is-playing" ""}}'
            {{on 'click' this.togglePlay}}
          >
            {{#if this.isPlaying}}
              <svg viewBox='0 0 24 24' fill='currentColor'>
                <rect x='6' y='4' width='4' height='16' />
                <rect x='14' y='4' width='4' height='16' />
              </svg>
            {{else}}
              <svg viewBox='0 0 24 24' fill='currentColor'>
                <path d='M8 5v14l11-7z' />
              </svg>
            {{/if}}
          </Button>
        </div>

        {{! Row 2: Sliders · Kit selector }}
        <div class='header-controls'>
          <div class='controls-group'>
            <div class='control-item'>
              <label class='ctrl-label'>BPM</label>
              <input
                type='range'
                min='60'
                max='200'
                value={{this.bpm}}
                aria-label='BPM'
                class='ctrl-slider'
                {{on 'input' this.updateBpm}}
              />
              <span class='ctrl-val'>{{this.bpm}}</span>
            </div>
            <div class='control-item'>
              <label class='ctrl-label'>SWING</label>
              <input
                type='range'
                min='0'
                max='100'
                value={{this.swing}}
                aria-label='Swing'
                class='ctrl-slider'
                {{on 'input' this.updateSwing}}
              />
              <span class='ctrl-val'>{{this.swing}}%</span>
            </div>
            <div class='control-item'>
              <label class='ctrl-label'>MASTER</label>
              <input
                type='range'
                min='0'
                max='100'
                value={{this.masterVolume}}
                aria-label='Master volume'
                class='ctrl-slider'
                {{on 'input' this.updateMasterVolume}}
              />
              <span class='ctrl-val'>{{this.masterVolume}}</span>
            </div>
          </div>

          <div class='kit-zone'>
            {{#if (gt this.availableKits.length 0)}}
              <label class='sr-only' for='kit-dropdown'>Select drum kit</label>
              <select
                id='kit-dropdown'
                class='kit-select'
                {{on 'change' this.handleKitSelection}}
              >
                {{#each this.availableKits as |kitCard|}}
                  <option
                    value={{kitCard.id}}
                    selected={{eq kitCard.kitName this.selectedKit}}
                  >{{kitCard.kitName}}</option>
                {{/each}}
              </select>
            {{else}}
              <span class='kit-fallback'>{{this.selectedKit}}</span>
            {{/if}}
          </div>
        </div>
      </header>

      {{! ═══ PATTERN LIBRARY ═══ }}
      {{#if (gt this.availablePatterns.length 0)}}
        <section class='pattern-library'>
          <div class='library-header'>
            <span class='library-title'>PATTERN LIBRARY</span>
            <span class='library-count'>{{this.availablePatterns.length}}</span>
          </div>
          <div class='library-scroll'>
            {{#each this.availablePatterns as |patternCard|}}
              <Button
                class='pattern-btn
                  {{if
                    (eq patternCard.id @model.currentPattern.id)
                    "active"
                    ""
                  }}'
                {{on 'click' (fn this.loadPreset patternCard)}}
              >
                <span
                  class='pattern-btn-name'
                >{{patternCard.patternName}}</span>
                <div class='pattern-btn-meta'>
                  {{#if patternCard.genre}}
                    <span class='pattern-genre'>{{patternCard.genre}}</span>
                  {{/if}}
                  {{#if patternCard.bpm}}
                    <span class='pattern-bpm'>{{patternCard.bpm}}</span>
                  {{/if}}
                </div>
              </Button>
            {{/each}}
          </div>
        </section>
      {{/if}}

      {{! ═══ SEQUENCER GRID ═══ }}
      <section class='sequencer'>
        <div class='seq-header'>
          <div class='controls-spacer'></div>
          <div class='step-numbers'>
            {{#each
              (array 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16)
              as |stepNum|
            }}
              <div
                class='step-num
                  {{if
                    (or
                      (eq stepNum 1)
                      (eq stepNum 5)
                      (eq stepNum 9)
                      (eq stepNum 13)
                    )
                    "beat"
                    ""
                  }}
                  {{if
                    (or (eq stepNum 5) (eq stepNum 9) (eq stepNum 13))
                    "group-gap"
                    ""
                  }}'
              >{{stepNum}}</div>
            {{/each}}
          </div>
        </div>

        {{#each
          (array 'kick' 'snare' 'hihat' 'openhat' 'clap' 'crash')
          as |instrument|
        }}
          <div class='inst-row row-{{instrument}}'>
            <div class='inst-controls'>
              {{! Row 1: LED + instrument name }}
              <div class='inst-top'>
                <div class='inst-led'></div>
                <span class='inst-name'>{{instrument}}</span>
              </div>
              {{! Row 2: volume slider + action buttons }}
              <div class='inst-bottom'>
                <input
                  type='range'
                  min='0'
                  max='100'
                  value='{{this.getInstrumentVolume instrument}}'
                  aria-label={{concat instrument ' volume'}}
                  class='vol-slider'
                  {{on 'input' (fn this.updateVolume instrument)}}
                />
                <div class='inst-actions'>
                  <button
                    class='act-btn'
                    title='Clear pattern'
                    {{on 'click' (fn this.clearPattern instrument)}}
                  >×</button>
                  <button
                    class='act-btn'
                    title='Fill pattern'
                    {{on 'click' (fn this.fillPattern instrument)}}
                  >■</button>
                  <button
                    class='act-btn'
                    title='Randomize'
                    {{on 'click' (fn this.randomizePattern instrument)}}
                  >?</button>
                </div>
              </div>
            </div>

            <div class='step-pads'>
              {{#each (array 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15) as |step|}}
                <button
                  class='pad
                    {{if
                      (get this.stepStates (concat instrument "-" step))
                      "on"
                      ""
                    }}
                    {{if (eq this.visualCurrentStep step) "now" ""}}
                    {{if
                      (or (eq step 4) (eq step 8) (eq step 12))
                      "group-start"
                      ""
                    }}'
                  {{on 'click' (fn this.toggleStep instrument step)}}
                ></button>
              {{/each}}
            </div>
          </div>
        {{/each}}
      </section>

      {{! ═══ FOOTER ═══ }}
      <footer class='studio-footer'>
        <span class='footer-kit'>{{this.selectedKit}}</span>
        <span class='footer-sep'>·</span>
        <span class='footer-label'>16-STEP</span>
        {{#if this.isPlaying}}
          <div class='footer-playing'>
            <div class='wave'></div>
            <div class='wave'></div>
            <div class='wave'></div>
            <div class='wave'></div>
            <div class='wave'></div>
            <span>PLAYING</span>
          </div>
        {{else}}
          <span class='footer-ready'>READY</span>
        {{/if}}
      </footer>
    </div>

    <style scoped>
      /* ═══ STUDIO SHELL — fills the card container fully ═══ */
      .studio {
        background: linear-gradient(160deg, #070a10 0%, #0d1220 100%);
        border-radius: var(--radius-xl, var(--boxel-border-radius-xl));
        padding: 1.125rem;
        color: #e2e8f0;
        font-family: var(--font-mono, 'JetBrains Mono', 'Fira Code', monospace);
        width: 100%;
        height: 100%;
        min-height: 0;
        box-sizing: border-box;
        display: flex;
        flex-direction: column;
        gap: 0.75rem;
        box-shadow:
          0 0 0 1px rgba(255, 255, 255, 0.06),
          0 24px 64px rgba(0, 0, 0, 0.85),
          inset 0 1px 0 rgba(255, 255, 255, 0.04);
        overflow: auto;
      }

      /* ═══ HEADER — two-row layout so nothing ever overflows ═══ */
      .studio-header {
        display: flex;
        flex-direction: column;
        gap: 0.625rem;
        padding: 0.75rem 0.875rem;
        background: linear-gradient(
          135deg,
          rgba(255, 255, 255, 0.04) 0%,
          rgba(255, 255, 255, 0.02) 100%
        );
        border-radius: var(--radius-lg, var(--boxel-border-radius-lg));
        border: 1px solid rgba(255, 255, 255, 0.07);
        flex-shrink: 0;
      }

      /* Row 1: Brand | spacer | LCD | Play button */
      .header-top {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        min-width: 0;
      }

      /* Row 2: Sliders + Kit selector */
      .header-controls {
        display: flex;
        align-items: center;
        gap: 1rem;
        padding-top: 0.5rem;
        border-top: 1px solid rgba(255, 255, 255, 0.05);
        flex-wrap: wrap;
        min-width: 0;
      }

      .brand {
        display: flex;
        align-items: center;
        gap: 0.625rem;
        flex-shrink: 0;
      }

      .brand-icon {
        width: 32px;
        height: 32px;
        color: #f59e0b;
        filter: drop-shadow(0 0 10px rgba(245, 158, 11, 0.7));
      }

      .brand-name {
        font-size: 0.9375rem;
        font-weight: 800;
        letter-spacing: 0.18em;
        background: linear-gradient(90deg, #f59e0b 0%, #f97316 100%);
        -webkit-background-clip: text;
        -webkit-text-fill-color: transparent;
        background-clip: text;
        line-height: 1;
        white-space: nowrap;
      }

      .brand-sub {
        font-size: 0.5rem;
        color: rgba(255, 255, 255, 0.3);
        letter-spacing: 0.2em;
        margin-top: 0.25rem;
        white-space: nowrap;
      }

      /* LCD Display — sits between brand and play btn in row 1 */
      .lcd-display {
        display: flex;
        align-items: center;
        gap: 0.875rem;
        padding: 0.5625rem 1rem;
        background: #030508;
        border-radius: var(--radius-sm, var(--boxel-border-radius-sm));
        border: 1px solid rgba(16, 185, 129, 0.2);
        box-shadow:
          inset 0 2px 10px rgba(0, 0, 0, 0.9),
          0 0 16px rgba(16, 185, 129, 0.08);
        margin-left: auto;
      }

      .lcd-row {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 0.1875rem;
        min-width: 2.5rem;
      }

      .lcd-label {
        font-size: 0.4375rem;
        color: rgba(16, 185, 129, 0.45);
        letter-spacing: 0.14em;
        font-weight: 700;
        text-transform: uppercase;
      }

      .lcd-val {
        font-size: 1.0625rem;
        color: #10b981;
        font-weight: 700;
        letter-spacing: 0.03em;
        text-shadow:
          0 0 10px rgba(16, 185, 129, 0.9),
          0 0 24px rgba(16, 185, 129, 0.4);
        min-width: 2ch;
        text-align: center;
        line-height: 1;
      }

      .lcd-divider {
        width: 1px;
        height: 28px;
        background: rgba(16, 185, 129, 0.15);
        flex-shrink: 0;
      }

      /* Sliders row */
      .controls-group {
        display: flex;
        gap: 1.25rem;
        align-items: center;
        flex-wrap: wrap;
      }

      .control-item {
        display: flex;
        align-items: center;
        gap: 0.5rem;
      }

      .ctrl-label {
        font-size: 0.5625rem;
        color: rgba(255, 255, 255, 0.4);
        letter-spacing: 0.12em;
        font-weight: 700;
        text-transform: uppercase;
        white-space: nowrap;
      }

      .ctrl-slider {
        width: 90px;
        height: 4px;
        -webkit-appearance: none;
        background: rgba(255, 255, 255, 0.1);
        border-radius: 99px;
        outline: none;
        cursor: pointer;
      }

      .ctrl-slider::-webkit-slider-thumb {
        -webkit-appearance: none;
        width: 15px;
        height: 15px;
        background: #f59e0b;
        border-radius: 50%;
        cursor: pointer;
        box-shadow: 0 0 8px rgba(245, 158, 11, 0.8);
      }

      .ctrl-slider::-moz-range-thumb {
        width: 15px;
        height: 15px;
        background: #f59e0b;
        border-radius: 50%;
        cursor: pointer;
        border: none;
        box-shadow: 0 0 8px rgba(245, 158, 11, 0.8);
      }

      .ctrl-val {
        font-size: 0.625rem;
        color: rgba(255, 255, 255, 0.6);
        min-width: 2.5ch;
        text-align: right;
        font-weight: 700;
      }

      .kit-zone {
        margin-left: auto;
        flex-shrink: 0;
      }

      .kit-select {
        background: rgba(255, 255, 255, 0.06);
        border: 1px solid rgba(255, 255, 255, 0.12);
        color: #e2e8f0;
        padding: 0.4375rem 0.75rem;
        border-radius: var(--radius-sm, var(--boxel-border-radius-sm));
        font-size: 0.75rem;
        font-family: var(--font-mono, monospace);
        cursor: pointer;
        outline: none;
        transition: border-color 0.15s ease;
      }

      .kit-select:hover,
      .kit-select:focus {
        border-color: rgba(245, 158, 11, 0.5);
      }

      .kit-fallback {
        font-size: 0.75rem;
        color: rgba(255, 255, 255, 0.4);
        font-style: italic;
      }

      /* Play Button */
      .play-btn {
        width: 50px;
        height: 50px;
        border-radius: 50%;
        background: linear-gradient(135deg, #10b981 0%, #059669 100%);
        color: white;
        display: flex;
        align-items: center;
        justify-content: center;
        cursor: pointer;
        transition: all 0.2s ease;
        box-shadow: 0 4px 16px rgba(16, 185, 129, 0.4);
        flex-shrink: 0;
        border: none;
      }

      .play-btn:hover {
        transform: scale(1.08);
        box-shadow: 0 6px 24px rgba(16, 185, 129, 0.6);
        filter: brightness(1.1);
      }

      .play-btn.is-playing {
        background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%);
        box-shadow: 0 4px 16px rgba(239, 68, 68, 0.5);
        animation: play-pulse 1.4s ease-in-out infinite;
      }

      @keyframes play-pulse {
        0%,
        100% {
          box-shadow: 0 4px 16px rgba(239, 68, 68, 0.5);
        }
        50% {
          box-shadow:
            0 4px 28px rgba(239, 68, 68, 0.75),
            0 0 40px rgba(239, 68, 68, 0.3);
        }
      }

      .play-btn svg {
        width: 18px;
        height: 18px;
      }

      /* ═══ PATTERN LIBRARY ═══ */
      .pattern-library {
        background: rgba(255, 255, 255, 0.022);
        border-radius: var(--radius, var(--boxel-border-radius));
        border: 1px solid rgba(255, 255, 255, 0.06);
        padding: 0.625rem 0.875rem;
      }

      .library-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        margin-bottom: 0.5rem;
      }

      .library-title {
        font-size: 0.5rem;
        letter-spacing: 0.18em;
        color: rgba(255, 255, 255, 0.3);
        font-weight: 700;
      }

      .library-count {
        font-size: 0.5rem;
        background: rgba(245, 158, 11, 0.12);
        color: #f59e0b;
        padding: 0.125rem 0.375rem;
        border-radius: 99px;
        border: 1px solid rgba(245, 158, 11, 0.25);
        font-weight: 700;
      }

      .library-scroll {
        display: flex;
        gap: 0.5rem;
        overflow-x: auto;
        padding-bottom: 0.25rem;
      }

      .library-scroll::-webkit-scrollbar {
        height: 2px;
      }

      .library-scroll::-webkit-scrollbar-track {
        background: rgba(255, 255, 255, 0.04);
        border-radius: 99px;
      }

      .library-scroll::-webkit-scrollbar-thumb {
        background: rgba(245, 158, 11, 0.35);
        border-radius: 99px;
      }

      .pattern-btn {
        flex-shrink: 0;
        min-width: 96px;
        padding: 0.375rem 0.625rem;
        background: rgba(255, 255, 255, 0.04);
        border: 1px solid rgba(255, 255, 255, 0.08);
        border-radius: var(--radius-sm, var(--boxel-border-radius-sm));
        color: rgba(255, 255, 255, 0.7);
        cursor: pointer;
        transition: all 0.15s ease;
        text-align: left;
        font-family: var(--font-mono, monospace);
      }

      .pattern-btn:hover {
        background: rgba(255, 255, 255, 0.08);
        border-color: rgba(245, 158, 11, 0.35);
      }

      .pattern-btn.active {
        background: linear-gradient(
          135deg,
          rgba(245, 158, 11, 0.2) 0%,
          rgba(249, 115, 22, 0.2) 100%
        );
        border-color: #f59e0b;
        box-shadow: 0 0 14px rgba(245, 158, 11, 0.2);
        color: #f59e0b;
      }

      .pattern-btn-name {
        display: block;
        font-size: 0.625rem;
        font-weight: 700;
        margin-bottom: 0.1875rem;
        color: inherit;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .pattern-btn-meta {
        display: flex;
        gap: 0.25rem;
      }

      .pattern-genre {
        font-size: 0.4375rem;
        color: rgba(255, 255, 255, 0.4);
        background: rgba(255, 255, 255, 0.07);
        padding: 0.0625rem 0.25rem;
        border-radius: 99px;
        text-transform: uppercase;
        letter-spacing: 0.06em;
      }

      .pattern-bpm {
        font-size: 0.4375rem;
        color: #22d3ee;
        background: rgba(34, 211, 238, 0.1);
        padding: 0.0625rem 0.25rem;
        border-radius: 99px;
        font-weight: 700;
      }

      /* ═══ SEQUENCER GRID — pads fill full width ═══ */
      .sequencer {
        background: linear-gradient(160deg, #060912, #0b1020);
        border-radius: var(--radius-lg, var(--boxel-border-radius-lg));
        padding: 1rem 1rem 0.875rem;
        border: 1px solid rgba(255, 255, 255, 0.05);
        box-shadow:
          inset 0 0 30px rgba(0, 0, 0, 0.6),
          inset 0 1px 0 rgba(255, 255, 255, 0.03);
        flex: 1;
        min-height: 0;
        /* Scroll horizontally when pads hit their min-width floor */
        overflow-x: auto;
        overflow-y: hidden;
      }

      /* Scrollable inner wrapper — keeps header and rows aligned */
      .seq-header {
        display: flex;
        align-items: center;
        margin-bottom: 0.5rem;
        min-width: max-content;
      }

      .controls-spacer {
        width: 168px;
        flex-shrink: 0;
      }

      /* Step numbers fill the same space as the pads below */
      .step-numbers {
        display: flex;
        flex: 1;
        gap: 4px;
        min-width: 0;
      }

      .step-num {
        flex: 1;
        min-width: 22px; /* floor — triggers scroll before collapsing */
        height: 20px;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 0.5625rem;
        color: rgba(255, 255, 255, 0.22);
        font-weight: 700;
      }

      .step-num.beat {
        color: rgba(245, 158, 11, 0.7);
      }

      /* Visual group separator — must equal .pad.group-start margin-left */
      .step-num.group-gap {
        margin-left: 10px;
      }

      /* ── Instrument Rows ── */
      .inst-row {
        display: flex;
        align-items: center;
        gap: 0.375rem;
        padding: 0.3rem 0 0.3rem 0.625rem;
        border-left: 4px solid var(--inst-color, #4b5563);
        border-radius: 0 4px 4px 0;
        transition: background 0.1s ease;
        margin-bottom: 0.25rem;
        min-width: max-content; /* keeps row from wrapping during scroll */
      }

      .inst-row:last-child {
        margin-bottom: 0;
      }

      .inst-row:hover {
        background: rgba(255, 255, 255, 0.02);
      }

      /* Per-instrument neon colors */
      .row-kick {
        --inst-color: #ef4444;
        --inst-glow: rgba(239, 68, 68, 0.65);
      }
      .row-snare {
        --inst-color: #3b82f6;
        --inst-glow: rgba(59, 130, 246, 0.65);
      }
      .row-hihat {
        --inst-color: #10b981;
        --inst-glow: rgba(16, 185, 129, 0.65);
      }
      .row-openhat {
        --inst-color: #f59e0b;
        --inst-glow: rgba(245, 158, 11, 0.65);
      }
      .row-clap {
        --inst-color: #8b5cf6;
        --inst-glow: rgba(139, 92, 246, 0.65);
      }
      .row-crash {
        --inst-color: #ec4899;
        --inst-glow: rgba(236, 72, 153, 0.65);
      }

      /* Fixed-width controls column — must equal .controls-spacer */
      .inst-controls {
        width: 180px;
        flex-shrink: 0;
        display: flex;
        flex-direction: column;
        justify-content: center;
        gap: 0.3rem;
        padding: 0.25rem 0;
      }

      /* Row 1: LED + name */
      .inst-top {
        display: flex;
        align-items: center;
        gap: 0.4rem;
      }

      /* Row 2: slider + action buttons */
      .inst-bottom {
        display: flex;
        align-items: center;
        gap: 0.375rem;
      }

      .inst-led {
        width: 8px;
        height: 8px;
        border-radius: 50%;
        background: var(--inst-color, #4b5563);
        box-shadow: 0 0 6px var(--inst-glow, rgba(75, 85, 99, 0.5));
        flex-shrink: 0;
      }

      .inst-name {
        font-size: 0.6875rem;
        font-weight: 800;
        color: var(--inst-color, #9ca3af);
        text-transform: uppercase;
        letter-spacing: 0.08em;
        white-space: nowrap;
      }

      /* Slider fills remaining space in bottom row */
      .vol-slider {
        flex: 1;
        min-width: 0;
        height: 3px;
        -webkit-appearance: none;
        background: rgba(255, 255, 255, 0.08);
        border-radius: 99px;
        outline: none;
        cursor: pointer;
      }

      .vol-slider::-webkit-slider-thumb {
        -webkit-appearance: none;
        width: 12px;
        height: 12px;
        background: var(--inst-color, #9ca3af);
        border-radius: 50%;
        cursor: pointer;
        box-shadow: 0 0 5px var(--inst-glow, rgba(75, 85, 99, 0.5));
      }

      .vol-slider::-moz-range-thumb {
        width: 12px;
        height: 12px;
        background: var(--inst-color, #9ca3af);
        border-radius: 50%;
        cursor: pointer;
        border: none;
      }

      .inst-actions {
        display: flex;
        gap: 0.1875rem;
        flex-shrink: 0;
      }

      .act-btn {
        width: 20px;
        height: 20px;
        background: transparent;
        border: 1px solid rgba(255, 255, 255, 0.09);
        color: rgba(255, 255, 255, 0.3);
        border-radius: 4px;
        cursor: pointer;
        font-size: 0.5rem;
        display: flex;
        align-items: center;
        justify-content: center;
        transition: all 0.15s ease;
        line-height: 1;
        font-family: var(--font-mono, monospace);
        flex-shrink: 0;
      }

      .act-btn:hover {
        border-color: var(--inst-color, #9ca3af);
        color: var(--inst-color, #9ca3af);
        background: rgba(255, 255, 255, 0.05);
      }

      /* ── Step Pads — stretch to fill remaining width ── */
      .step-pads {
        display: flex;
        flex: 1;
        gap: 4px; /* single spacing source — no margin on individual pads */
        min-width: 0;
      }

      .pad {
        flex: 1;
        min-width: 22px; /* floor — triggers sequencer scroll before squishing */
        height: 32px;
        border: none;
        background: rgba(255, 255, 255, 0.045);
        border-radius: 4px;
        cursor: pointer;
        transition: all 0.08s ease;
        position: relative;
        outline: 1px solid rgba(255, 255, 255, 0.07);
        box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.06);
      }

      /* Extra gap before beat groups 2/3/4 — must match .step-num.group-gap */
      .pad.group-start {
        margin-left: 10px;
      }

      .pad:hover {
        background: rgba(255, 255, 255, 0.1);
        outline-color: var(--inst-color, rgba(255, 255, 255, 0.18));
      }

      .pad.on {
        background: var(--inst-color, #4b5563);
        outline-color: var(--inst-color, #4b5563);
        box-shadow:
          0 0 12px var(--inst-glow, rgba(75, 85, 99, 0.5)),
          inset 0 1px 0 rgba(255, 255, 255, 0.35),
          inset 0 0 8px rgba(255, 255, 255, 0.08);
      }

      .pad.now {
        outline: 1px solid rgba(255, 255, 255, 0.4);
        background: rgba(255, 255, 255, 0.09);
      }

      .pad.on.now {
        filter: brightness(1.35);
        box-shadow:
          0 0 20px var(--inst-glow, rgba(75, 85, 99, 0.8)),
          0 0 8px var(--inst-glow, rgba(75, 85, 99, 0.8)),
          inset 0 0 10px rgba(255, 255, 255, 0.4),
          inset 0 1px 0 rgba(255, 255, 255, 0.5);
        animation: pad-flash 0.5s ease-in-out infinite alternate;
      }

      @keyframes pad-flash {
        from {
          filter: brightness(1.2);
        }
        to {
          filter: brightness(1.65);
        }
      }

      /* ═══ FOOTER ═══ */
      .studio-footer {
        display: flex;
        align-items: center;
        gap: 0.625rem;
        font-size: 0.625rem;
        color: rgba(255, 255, 255, 0.25);
        letter-spacing: 0.1em;
        padding: 0.125rem 0.25rem;
      }

      .footer-kit {
        color: rgba(255, 255, 255, 0.55);
        font-weight: 700;
      }

      .footer-sep {
        color: rgba(255, 255, 255, 0.15);
      }

      .footer-label {
        color: rgba(255, 255, 255, 0.25);
      }

      .footer-ready {
        margin-left: auto;
        color: rgba(255, 255, 255, 0.25);
        letter-spacing: 0.14em;
      }

      .footer-playing {
        margin-left: auto;
        display: flex;
        align-items: center;
        gap: 0.4rem;
        color: #10b981;
      }

      .footer-playing span {
        font-weight: 800;
        letter-spacing: 0.18em;
        text-shadow: 0 0 8px rgba(16, 185, 129, 0.6);
      }

      .wave {
        width: 2px;
        background: #10b981;
        border-radius: 99px;
        box-shadow: 0 0 4px rgba(16, 185, 129, 0.6);
        animation: wave-anim 0.7s ease-in-out infinite;
      }

      .wave:nth-child(1) {
        height: 5px;
        animation-delay: 0s;
      }

      .wave:nth-child(2) {
        height: 9px;
        animation-delay: 0.1s;
      }

      .wave:nth-child(3) {
        height: 7px;
        animation-delay: 0.2s;
      }

      .wave:nth-child(4) {
        height: 11px;
        animation-delay: 0.15s;
      }

      .wave:nth-child(5) {
        height: 6px;
        animation-delay: 0.05s;
      }

      @keyframes wave-anim {
        0%,
        100% {
          transform: scaleY(0.45);
          opacity: 0.6;
        }
        50% {
          transform: scaleY(1);
          opacity: 1;
        }
      }

      .sr-only {
        position: absolute;
        width: 1px;
        height: 1px;
        padding: 0;
        margin: -1px;
        overflow: hidden;
        clip: rect(0, 0, 0, 0);
        border: 0;
      }

      /* ═══ RESPONSIVE ═══ */
      @media (max-width: 768px) {
        .studio {
          padding: 0.75rem;
          gap: 0.5rem;
        }

        .header-top {
          gap: 0.5rem;
        }

        .brand-name {
          font-size: 0.75rem;
          letter-spacing: 0.14em;
        }

        .brand-sub {
          font-size: 0.375rem;
        }

        .brand-icon {
          width: 26px;
          height: 26px;
        }

        .lcd-display {
          gap: 0.5rem;
          padding: 0.4375rem 0.625rem;
        }

        .lcd-val {
          font-size: 0.875rem;
        }

        .header-controls {
          gap: 0.75rem;
        }

        .ctrl-slider {
          width: 64px;
        }

        .ctrl-label {
          font-size: 0.4375rem;
        }

        .ctrl-val {
          font-size: 0.5rem;
        }

        .kit-select {
          font-size: 0.625rem;
          padding: 0.375rem 0.5rem;
        }

        .play-btn {
          width: 42px;
          height: 42px;
        }

        /* pads are flex:1 — just shrink the controls column */
        .controls-spacer {
          width: 136px;
        }

        .inst-controls {
          width: 136px;
        }

        .inst-name {
          font-size: 0.5625rem;
        }

        .pad {
          height: 26px;
        }

        .act-btn {
          width: 18px;
          height: 18px;
        }
      }

      @media (max-width: 520px) {
        .controls-spacer {
          width: 108px;
        }

        .inst-controls {
          width: 108px;
        }

        .inst-name {
          font-size: 0.4375rem;
          letter-spacing: 0.05em;
        }

        .inst-led {
          width: 6px;
          height: 6px;
        }

        .act-btn {
          width: 16px;
          height: 16px;
          font-size: 0.375rem;
        }

        .pad {
          height: 22px;
          margin: 0 1px;
        }

        .pad.group-start {
          margin-left: 6px;
        }

        .step-num.group-gap {
          margin-left: 6px;
        }

        .step-num {
          font-size: 0.4375rem;
        }
      }
    </style>
  </template>
}

export class BeatMakerCard extends CardDef {
  static displayName = 'Beat Maker';
  static icon = MusicIcon;
  static prefersWideFormat = true;

  @field bpm = contains(NumberField);
  @field pattern = contains(StringField);
  @field instrumentKit = contains(StringField);
  @field swing = contains(NumberField);
  @field masterVolume = contains(NumberField);
  @field currentPattern = linksTo(() => BeatPatternCard);
  @field currentKit = linksTo(() => DrumKitCard);
  @field availableKits = linksToMany(() => DrumKitCard);
  @field availablePatterns = linksToMany(() => BeatPatternCard);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: BeatMakerCard) {
      return 'Beat Maker';
    },
  });

  static isolated = BeatMakerIsolated;

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <div class='fitted-container'>

        {{! BADGE FORMAT (≤150px × ≤169px) }}
        <div class='badge-format'>
          <div class='badge-content'>
            <div class='badge-pads'>
              <div class='mini-pad on'></div>
              <div class='mini-pad'></div>
              <div class='mini-pad on'></div>
              <div class='mini-pad'></div>
            </div>
            <div class='badge-info'>
              <div class='badge-title'>Beat Maker</div>
              <div class='badge-bpm'>{{if @model.bpm @model.bpm 120}} BPM</div>
            </div>
          </div>
        </div>

        {{! STRIP FORMAT (>150px, ≤169px height) }}
        <div class='strip-format'>
          <div class='strip-content'>
            <div class='strip-eq'>
              <div class='eq-bar h-60'></div>
              <div class='eq-bar h-30'></div>
              <div class='eq-bar h-85'></div>
              <div class='eq-bar h-45'></div>
              <div class='eq-bar h-70'></div>
              <div class='eq-bar active h-90'></div>
              <div class='eq-bar h-55'></div>
            </div>
            <div class='strip-info'>
              <div class='strip-title'>Rhythm Studio</div>
              <div class='strip-sub'>
                {{if @model.bpm @model.bpm 120}}
                BPM ·
                {{if
                  @model.currentKit.kitName
                  @model.currentKit.kitName
                  (if @model.instrumentKit @model.instrumentKit '808')
                }}
              </div>
            </div>
            <div class='strip-tags'>
              <span class='strip-tag'>16-Step</span>
            </div>
          </div>
        </div>

        {{! TILE FORMAT (≤399px, ≥170px height) }}
        <div class='tile-format'>
          <div class='tile-hero'>
            <div class='tile-grid'>
              <div class='tile-seq-row'>
                <div class='tile-pad on kick'></div>
                <div class='tile-pad'></div>
                <div class='tile-pad'></div>
                <div class='tile-pad on kick'></div>
              </div>
              <div class='tile-seq-row'>
                <div class='tile-pad'></div>
                <div class='tile-pad on snare'></div>
                <div class='tile-pad'></div>
                <div class='tile-pad on snare'></div>
              </div>
              <div class='tile-seq-row'>
                <div class='tile-pad on hihat'></div>
                <div class='tile-pad on hihat'></div>
                <div class='tile-pad on hihat'></div>
                <div class='tile-pad on hihat'></div>
              </div>
            </div>
          </div>
          <div class='tile-body'>
            <h3 class='tile-title'>Beat Maker</h3>
            <div class='tile-specs'>
              <div class='tile-spec'>
                <span class='spec-k'>BPM</span>
                <span class='spec-v'>{{if @model.bpm @model.bpm 120}}</span>
              </div>
              <div class='tile-spec'>
                <span class='spec-k'>Kit</span>
                <span class='spec-v'>{{if
                    @model.currentKit.kitName
                    @model.currentKit.kitName
                    (if @model.instrumentKit @model.instrumentKit '808')
                  }}</span>
              </div>
            </div>
            <div class='tile-pills'>
              <span class='pill'>16-Step</span>
              <span class='pill'>Synth</span>
              <span class='pill'>Swing</span>
            </div>
          </div>
        </div>

        {{! CARD FORMAT (≥400px, ≥170px height) }}
        <div class='card-format'>
          <div class='card-hero'>
            <div class='card-info'>
              <h3 class='card-title'>Beat Maker Studio</h3>
              <p class='card-desc'>Professional drum machine with dynamic
                synthesis and 16-step pattern sequencing</p>
            </div>
            <div class='card-machine'>
              <div class='machine-lcd'>
                <div class='m-row'>
                  <span class='m-label'>BPM</span>
                  <span class='m-val'>{{if @model.bpm @model.bpm 120}}</span>
                </div>
                <div class='m-row'>
                  <span class='m-label'>KIT</span>
                  <span class='m-val'>{{if
                      @model.currentKit.kitName
                      @model.currentKit.kitName
                      (if @model.instrumentKit @model.instrumentKit '808')
                    }}</span>
                </div>
              </div>
              <div class='machine-knobs'>
                <div class='knob'></div>
                <div class='knob'></div>
                <div class='knob'></div>
              </div>
            </div>
          </div>

          <div class='card-seq-preview'>
            <div class='seq-track track-kick'>
              <div class='s-pad on'></div>
              <div class='s-pad'></div>
              <div class='s-pad'></div>
              <div class='s-pad'></div>
              <div class='s-pad on'></div>
              <div class='s-pad'></div>
              <div class='s-pad'></div>
              <div class='s-pad'></div>
            </div>
            <div class='seq-track track-snare'>
              <div class='s-pad'></div>
              <div class='s-pad'></div>
              <div class='s-pad'></div>
              <div class='s-pad on'></div>
              <div class='s-pad'></div>
              <div class='s-pad'></div>
              <div class='s-pad'></div>
              <div class='s-pad on'></div>
            </div>
            <div class='seq-track track-hihat'>
              <div class='s-pad on'></div>
              <div class='s-pad on'></div>
              <div class='s-pad on'></div>
              <div class='s-pad on'></div>
              <div class='s-pad on'></div>
              <div class='s-pad on'></div>
              <div class='s-pad on'></div>
              <div class='s-pad on'></div>
            </div>
          </div>

          <div class='card-stats'>
            <div class='stat'>
              <div class='stat-val'>{{if
                  @model.availablePatterns.length
                  @model.availablePatterns.length
                  8
                }}</div>
              <div class='stat-label'>Patterns</div>
            </div>
            <div class='stat'>
              <div class='stat-val'>{{if
                  @model.availableKits.length
                  @model.availableKits.length
                  6
                }}</div>
              <div class='stat-label'>Drum Kits</div>
            </div>
            <div class='stat'>
              <div class='stat-val'>16</div>
              <div class='stat-label'>Steps</div>
            </div>
          </div>

          <div class='card-features'>
            <span class='feat-pill'>Dynamic Synthesis</span>
            <span class='feat-pill'>Pattern Library</span>
            <span class='feat-pill'>Real-time Control</span>
            <span class='feat-pill'>Kit Management</span>
          </div>
        </div>
      </div>

      <style scoped>
        .fitted-container {
          container-type: size;
          width: 100%;
          height: 100%;
          font-family: var(
            --font-mono,
            'JetBrains Mono',
            'Fira Code',
            monospace
          );
        }

        /* Hide all formats by default */
        .badge-format,
        .strip-format,
        .tile-format,
        .card-format {
          display: none;
          width: 100%;
          height: 100%;
          padding: clamp(0.25rem, 3%, 0.75rem);
          box-sizing: border-box;
          background: linear-gradient(145deg, #070a10 0%, #0e1422 100%);
          border-radius: var(--radius-xl, var(--boxel-border-radius-xl));
          overflow: hidden;
        }

        /* ── BADGE FORMAT (≤150px × ≤169px) ── */
        @container (max-width: 150px) and (max-height: 169px) {
          .badge-format {
            display: flex;
            align-items: center;
          }
        }

        .badge-content {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          width: 100%;
        }

        .badge-pads {
          display: grid;
          grid-template-columns: repeat(2, 10px);
          grid-template-rows: repeat(2, 10px);
          gap: 3px;
          flex-shrink: 0;
        }

        .mini-pad {
          width: 10px;
          height: 10px;
          background: rgba(245, 158, 11, 0.12);
          border-radius: 2px;
          border: 1px solid rgba(245, 158, 11, 0.2);
        }

        .mini-pad.on {
          background: #f59e0b;
          box-shadow: 0 0 6px rgba(245, 158, 11, 0.7);
          border-color: #f59e0b;
          animation: badge-beat 1.4s ease-in-out infinite;
        }

        @keyframes badge-beat {
          0%,
          100% {
            opacity: 1;
          }
          50% {
            opacity: 0.55;
          }
        }

        .badge-info {
          flex: 1;
          min-width: 0;
        }

        .badge-title {
          font-size: 0.6875rem;
          font-weight: 800;
          color: #f59e0b;
          line-height: 1.1;
          margin-bottom: 0.125rem;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .badge-bpm {
          font-size: 0.5rem;
          color: rgba(255, 255, 255, 0.5);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        /* ── STRIP FORMAT (>150px, ≤169px height) ── */
        @container (min-width: 151px) and (max-height: 169px) {
          .strip-format {
            display: flex;
            align-items: center;
          }
        }

        .strip-content {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          width: 100%;
        }

        .strip-eq {
          display: flex;
          align-items: flex-end;
          gap: 2px;
          height: 28px;
          flex-shrink: 0;
        }

        .eq-bar {
          width: 4px;
          background: rgba(245, 158, 11, 0.3);
          border-radius: 1px;
          animation: eq-pulse 1s ease-in-out infinite;
        }

        .eq-bar.active {
          background: #f59e0b;
          box-shadow: 0 0 6px rgba(245, 158, 11, 0.6);
        }

        .eq-bar:nth-child(1) {
          animation-delay: 0s;
        }
        .eq-bar:nth-child(2) {
          animation-delay: 0.12s;
        }
        .eq-bar:nth-child(3) {
          animation-delay: 0.08s;
        }
        .eq-bar:nth-child(4) {
          animation-delay: 0.2s;
        }
        .eq-bar:nth-child(5) {
          animation-delay: 0.05s;
        }
        .eq-bar:nth-child(6) {
          animation-delay: 0.15s;
        }
        .eq-bar:nth-child(7) {
          animation-delay: 0.1s;
        }

        /* EQ bar heights via class (avoids inline style attributes) */
        .eq-bar.h-30 {
          height: 30%;
        }
        .eq-bar.h-45 {
          height: 45%;
        }
        .eq-bar.h-55 {
          height: 55%;
        }
        .eq-bar.h-60 {
          height: 60%;
        }
        .eq-bar.h-70 {
          height: 70%;
        }
        .eq-bar.h-85 {
          height: 85%;
        }
        .eq-bar.h-90 {
          height: 90%;
        }

        @keyframes eq-pulse {
          0%,
          100% {
            transform: scaleY(0.6);
            opacity: 0.7;
          }
          50% {
            transform: scaleY(1.2);
            opacity: 1;
          }
        }

        .strip-info {
          flex: 1;
          min-width: 0;
        }

        .strip-title {
          font-size: 0.8125rem;
          font-weight: 800;
          color: #f59e0b;
          line-height: 1.1;
          margin-bottom: 0.1875rem;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          letter-spacing: 0.05em;
        }

        .strip-sub {
          font-size: 0.625rem;
          color: rgba(255, 255, 255, 0.5);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .strip-tags {
          flex-shrink: 0;
        }

        .strip-tag {
          font-size: 0.5rem;
          padding: 0.125rem 0.375rem;
          background: rgba(245, 158, 11, 0.12);
          color: #f59e0b;
          border: 1px solid rgba(245, 158, 11, 0.25);
          border-radius: 99px;
          font-weight: 700;
          letter-spacing: 0.06em;
          white-space: nowrap;
        }

        /* ── TILE FORMAT (≤399px, ≥170px height) ── */
        @container (max-width: 399px) and (min-height: 170px) {
          .tile-format {
            display: flex;
            flex-direction: column;
          }
        }

        .tile-hero {
          background: linear-gradient(135deg, #f59e0b 0%, #f97316 100%);
          border-radius: var(--radius-lg, var(--boxel-border-radius-lg));
          padding: 0.875rem;
          display: flex;
          align-items: center;
          justify-content: center;
          margin-bottom: 0.75rem;
        }

        .tile-grid {
          display: flex;
          flex-direction: column;
          gap: 4px;
        }

        .tile-seq-row {
          display: flex;
          gap: 4px;
        }

        .tile-pad {
          width: 12px;
          height: 10px;
          background: rgba(255, 255, 255, 0.2);
          border-radius: 2px;
        }

        .tile-pad.on {
          background: rgba(255, 255, 255, 0.9);
          box-shadow: 0 0 6px rgba(255, 255, 255, 0.7);
        }

        .tile-body {
          flex: 1;
          display: flex;
          flex-direction: column;
          gap: 0.625rem;
        }

        .tile-title {
          font-size: 1rem;
          font-weight: 800;
          color: #f59e0b;
          margin: 0;
          letter-spacing: 0.05em;
        }

        .tile-specs {
          display: flex;
          flex-direction: column;
          gap: 0.3125rem;
        }

        .tile-spec {
          display: flex;
          justify-content: space-between;
          align-items: center;
        }

        .spec-k {
          font-size: 0.625rem;
          color: rgba(255, 255, 255, 0.45);
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.1em;
        }

        .spec-v {
          font-size: 0.75rem;
          color: #f59e0b;
          font-weight: 700;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          max-width: 60%;
          text-align: right;
        }

        .tile-pills {
          display: flex;
          flex-wrap: wrap;
          gap: 0.3125rem;
          margin-top: auto;
        }

        .pill {
          padding: 0.1875rem 0.4375rem;
          background: rgba(245, 158, 11, 0.12);
          border: 1px solid rgba(245, 158, 11, 0.25);
          color: #f59e0b;
          font-size: 0.5rem;
          font-weight: 700;
          border-radius: 99px;
          letter-spacing: 0.06em;
        }

        /* ── CARD FORMAT (≥400px, ≥170px height) ── */
        @container (min-width: 400px) and (min-height: 170px) {
          .card-format {
            display: flex;
            flex-direction: column;
            gap: 0.875rem;
          }
        }

        .card-hero {
          display: flex;
          align-items: center;
          justify-content: space-between;
          background: linear-gradient(135deg, #f59e0b 0%, #f97316 100%);
          padding: 0.875rem 1rem;
          border-radius: var(--radius-lg, var(--boxel-border-radius-lg));
          gap: 1rem;
        }

        .card-info {
          flex: 1;
          min-width: 0;
        }

        .card-title {
          font-size: 1.125rem;
          font-weight: 800;
          color: white;
          margin: 0 0 0.3125rem 0;
          letter-spacing: 0.04em;
          line-height: 1.2;
        }

        .card-desc {
          font-size: 0.6875rem;
          color: rgba(255, 255, 255, 0.85);
          margin: 0;
          line-height: 1.45;
        }

        .card-machine {
          flex-shrink: 0;
          padding: 0.625rem;
          background: rgba(7, 10, 16, 0.75);
          border-radius: var(--radius, var(--boxel-border-radius));
          min-width: 100px;
          border: 1px solid rgba(245, 158, 11, 0.3);
        }

        .machine-lcd {
          background: #030508;
          padding: 0.375rem 0.5rem;
          border-radius: 3px;
          margin-bottom: 0.5rem;
          border: 1px solid rgba(16, 185, 129, 0.2);
        }

        .m-row {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 0.1875rem;
        }

        .m-row:last-child {
          margin-bottom: 0;
        }

        .m-label {
          font-size: 0.4375rem;
          color: rgba(16, 185, 129, 0.5);
          font-weight: 700;
          letter-spacing: 0.1em;
        }

        .m-val {
          font-size: 0.625rem;
          color: #10b981;
          font-weight: 700;
          text-shadow: 0 0 6px rgba(16, 185, 129, 0.7);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          max-width: 60px;
          text-align: right;
        }

        .machine-knobs {
          display: flex;
          justify-content: space-between;
          gap: 0.25rem;
        }

        .knob {
          flex: 1;
          height: 14px;
          background: #1a1f2e;
          border: 2px solid #f59e0b;
          border-radius: 50%;
          position: relative;
        }

        .knob::after {
          content: '';
          position: absolute;
          top: 2px;
          left: 50%;
          transform: translateX(-50%);
          width: 2px;
          height: 4px;
          background: #f59e0b;
          border-radius: 1px;
        }

        /* Sequencer preview */
        .card-seq-preview {
          display: flex;
          flex-direction: column;
          gap: 3px;
          padding: 0.625rem 0.75rem;
          background: rgba(6, 9, 18, 0.8);
          border-radius: var(--radius, var(--boxel-border-radius));
          border: 1px solid rgba(255, 255, 255, 0.05);
        }

        .seq-track {
          display: flex;
          gap: 3px;
        }

        .s-pad {
          flex: 1;
          height: 10px;
          background: rgba(255, 255, 255, 0.05);
          border-radius: 2px;
          border: 1px solid rgba(255, 255, 255, 0.06);
        }

        .track-kick .s-pad.on {
          background: #ef4444;
          box-shadow: 0 0 5px rgba(239, 68, 68, 0.5);
          border-color: #ef4444;
        }

        .track-snare .s-pad.on {
          background: #3b82f6;
          box-shadow: 0 0 5px rgba(59, 130, 246, 0.5);
          border-color: #3b82f6;
        }

        .track-hihat .s-pad.on {
          background: #10b981;
          box-shadow: 0 0 5px rgba(16, 185, 129, 0.5);
          border-color: #10b981;
        }

        /* Stats */
        .card-stats {
          display: grid;
          grid-template-columns: repeat(3, 1fr);
          gap: 0.5rem;
        }

        .stat {
          text-align: center;
          padding: 0.5rem;
          background: rgba(255, 255, 255, 0.03);
          border-radius: var(--radius-sm, var(--boxel-border-radius-sm));
          border: 1px solid rgba(255, 255, 255, 0.05);
        }

        .stat-val {
          font-size: 1.125rem;
          font-weight: 800;
          color: #f59e0b;
          line-height: 1;
          margin-bottom: 0.25rem;
          text-shadow: 0 0 12px rgba(245, 158, 11, 0.4);
        }

        .stat-label {
          font-size: 0.4375rem;
          color: rgba(255, 255, 255, 0.35);
          text-transform: uppercase;
          letter-spacing: 0.12em;
          font-weight: 600;
        }

        /* Feature pills */
        .card-features {
          display: flex;
          flex-wrap: wrap;
          gap: 0.375rem;
          margin-top: auto;
        }

        .feat-pill {
          padding: 0.3125rem 0.625rem;
          background: linear-gradient(
            135deg,
            rgba(245, 158, 11, 0.18) 0%,
            rgba(249, 115, 22, 0.18) 100%
          );
          border: 1px solid rgba(245, 158, 11, 0.3);
          color: #f59e0b;
          font-size: 0.5625rem;
          font-weight: 700;
          border-radius: 99px;
          letter-spacing: 0.06em;
        }
      </style>
    </template>
  };
}
