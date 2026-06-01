import {
  FieldDef,
  field,
  contains,
  linksTo,
  Component,
} from 'https://cardstack.com/base/card-api';
import { AudioDef } from 'https://cardstack.com/base/audio-file-def';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import BooleanField from 'https://cardstack.com/base/boolean';
import DateTimeField from 'https://cardstack.com/base/datetime';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { fn, array, hash, concat } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import { modifier } from 'ember-modifier';
import {
  BaseAudioPlayer,
  type AudioFieldConfiguration,
  type AudioFieldOptions,
  type AudioPresentationStyle,
} from './audio/components/base-audio-player';
import { WaveformPlayer } from './audio/components/waveform-player';
import { MiniPlayer } from './audio/components/mini-player';
import { AlbumCoverPlayer } from './audio/components/album-cover-player';
import { TrimEditor } from './audio/components/trim-editor';
import { PlaylistRow } from './audio/components/playlist-row';
import { VolumeControl } from './audio/components/volume-control';
import { eq, or, and, bool, not } from '@cardstack/boxel-ui/helpers';
import {
  BoxelInput,
  Button,
  BoxelSelect,
  FieldContainer,
} from '@cardstack/boxel-ui/components';
import MusicIcon from '@cardstack/boxel-icons/music';
import PlayIcon from '@cardstack/boxel-icons/play';
import PauseIcon from '@cardstack/boxel-icons/pause';

export type {
  AudioFieldConfiguration,
  AudioFieldOptions,
  AudioPresentationStyle,
};

class AudioFieldEdit extends Component<typeof AudioField> {
  <template>
    <div class='audio-edit' data-test-audio-edit>
      <FieldContainer @label='Audio file'>
        <@fields.file />
      </FieldContainer>

      <FieldContainer @label='Title'>
        <BoxelInput
          @value={{@model.cardTitle}}
          @onInput={{fn (mut @model.cardTitle)}}
          placeholder='Track title'
          @disabled={{not @canEdit}}
        />
      </FieldContainer>

      <FieldContainer @label='Artist'>
        <BoxelInput
          @value={{@model.artist}}
          @onInput={{fn (mut @model.artist)}}
          placeholder='Artist name'
          @disabled={{not @canEdit}}
        />
      </FieldContainer>
    </div>

    <style scoped>
      .audio-edit {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-lg);
      }
    </style>
  </template>
}

class AudioFieldFitted extends Component<typeof AudioField> {
  @tracked isPlaying = false;
  @tracked currentTime = 0;
  @tracked audioDuration = 0;
  @tracked isHovering = false;
  audioElement: HTMLAudioElement | null = null;

  get progressPercentage(): number {
    if (!this.audioDuration || this.audioDuration === 0) return 0;
    return (this.currentTime / this.audioDuration) * 100;
  }

  setupAudio = modifier((element: HTMLAudioElement) => {
    this.audioElement = element;
    return () => {
      this.audioElement = null;
    };
  });

  @action
  togglePlay() {
    if (!this.audioElement) return;

    if (this.isPlaying) {
      this.audioElement.pause();
    } else {
      this.audioElement.play();
    }
  }

  @action
  handlePlay() {
    this.isPlaying = true;
  }

  @action
  handlePause() {
    this.isPlaying = false;
  }

  @action
  handleTimeUpdate(event: Event) {
    const audio = event.target as HTMLAudioElement;
    this.currentTime = audio.currentTime;
  }

  @action
  handleLoadedMetadata(event: Event) {
    const audio = event.target as HTMLAudioElement;
    this.audioDuration = audio.duration;
  }

  @action
  handleMouseEnter() {
    this.isHovering = true;
  }

  @action
  handleMouseLeave() {
    this.isHovering = false;
  }

  formatTime(seconds: number): string {
    if (!seconds || isNaN(seconds)) return '0:00';
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  }

  <template>
    {{#if @model.url}}
      <div
        class='audio-card'
        data-test-audio-fitted
        {{on 'mouseenter' this.handleMouseEnter}}
        {{on 'mouseleave' this.handleMouseLeave}}
        style={{htmlSafe 'width: 100%; height: 100%'}}
      >
        <audio
          {{this.setupAudio}}
          src={{@model.url}}
          {{on 'play' this.handlePlay}}
          {{on 'pause' this.handlePause}}
          {{on 'timeupdate' this.handleTimeUpdate}}
          {{on 'loadedmetadata' this.handleLoadedMetadata}}
        >
          <track kind='captions' />
        </audio>

        <div class='card-background'>
          <svg
            class='background-icon'
            viewBox='0 0 24 24'
            fill='none'
            stroke='currentColor'
            stroke-width='2'
          >
            <path d='M9 18V5l12-2v13' />
            <circle cx='6' cy='18' r='3' />
            <circle cx='18' cy='16' r='3' />
          </svg>
        </div>

        {{#if (or this.isHovering this.isPlaying)}}
          <div class='play-overlay'>
            <Button
              @kind='primary'
              class='play-overlay-button'
              {{on 'click' this.togglePlay}}
            >
              {{#if this.isPlaying}}
                <PauseIcon width='32' height='32' />
              {{else}}
                <PlayIcon width='32' height='32' />
              {{/if}}
            </Button>
          </div>
        {{/if}}

        {{#if this.audioDuration}}
          <div class='duration-badge'>
            {{this.formatTime this.audioDuration}}
          </div>
        {{/if}}

        <div class='card-footer'>
          <div class='card-title'>{{@model.displayTitle}}</div>
          {{#if @model.artist}}
            <div class='card-artist'>{{@model.artist}}</div>
          {{/if}}

          {{#if (and this.isPlaying (bool this.audioDuration))}}
            <div class='progress-bar'>
              <div
                class='progress-fill'
                style={{htmlSafe
                  (concat 'width: ' this.progressPercentage '%')
                }}
              ></div>
            </div>
          {{/if}}
        </div>
      </div>
    {{else}}
      <div
        class='audio-card-placeholder'
        data-test-audio-fitted-placeholder
        style={{htmlSafe 'width: 100%; height: 100%'}}
      >
        <svg
          viewBox='0 0 24 24'
          fill='none'
          stroke='currentColor'
          stroke-width='2'
        >
          <path d='M9 18V5l12-2v13' />
          <circle cx='6' cy='18' r='3' />
          <circle cx='18' cy='16' r='3' />
        </svg>
        <span>No audio</span>
      </div>
    {{/if}}

    <style scoped>
      .audio-card {
        position: relative;
        background: var(--card, #ffffff);
        border-radius: var(--radius, 0.5rem);
        overflow: hidden;
        display: flex;
        flex-direction: column;
        box-shadow: var(--shadow-sm, 0 1px 2px 0 rgb(0 0 0 / 0.05));
        transition: all 0.2s;
      }

      .audio-card:hover {
        box-shadow: var(--shadow-md, 0 4px 6px -1px rgb(0 0 0 / 0.1));
      }

      .card-background {
        flex: 1;
        background: linear-gradient(
          135deg,
          var(--primary, #3b82f6),
          var(--accent, #60a5fa)
        );
        display: flex;
        align-items: center;
        justify-content: center;
        position: relative;
        min-height: 8rem;
      }

      .background-icon {
        width: 4rem;
        height: 4rem;
        color: rgba(255, 255, 255, 0.3);
      }

      .play-overlay {
        position: absolute;
        inset: 0;
        background: rgba(0, 0, 0, 0.4);
        display: flex;
        align-items: center;
        justify-content: center;
        backdrop-filter: blur(2px);
      }

      .play-overlay-button {
        width: 4rem;
        height: 4rem;
        border-radius: 50%;
        background: white !important;
        color: var(--primary, #3b82f6) !important;
        box-shadow:
          0 4px 6px -1px rgb(0 0 0 / 0.1),
          0 2px 4px -2px rgb(0 0 0 / 0.1) !important;
      }

      .play-overlay-button:hover {
        background: rgba(255, 255, 255, 0.95) !important;
        transform: scale(1.05);
      }

      .duration-badge {
        position: absolute;
        top: 0.5rem;
        right: 0.5rem;
        padding: 0.25rem 0.5rem;
        background: rgba(0, 0, 0, 0.7);
        color: white;
        font-size: 0.75rem;
        border-radius: 0.25rem;
        backdrop-filter: blur(4px);
      }

      .card-footer {
        padding: 0.75rem;
        background: var(--card, #ffffff);
      }

      .card-title {
        font-weight: 600;
        font-size: 0.875rem;
        color: var(--foreground, #1f2937);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .card-artist {
        font-size: 0.75rem;
        color: var(--muted-foreground, #6b7280);
        margin-top: 0.125rem;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .progress-bar {
        height: 0.25rem;
        background: var(--muted, #e5e7eb);
        border-radius: 0.125rem;
        overflow: hidden;
        margin-top: 0.5rem;
      }

      .progress-fill {
        height: 100%;
        background: var(--primary, #3b82f6);
        transition: width 0.1s linear;
      }

      .audio-card-placeholder {
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 0.5rem;
        background: var(--muted, #f3f4f6);
        border-radius: var(--radius, 0.5rem);
        color: var(--muted-foreground, #6b7280);
        font-size: 0.875rem;
        font-style: italic;
      }

      .audio-card-placeholder svg {
        width: 2rem;
        height: 2rem;
      }
    </style>
  </template>
}

export default class AudioField extends FieldDef {
  static displayName = 'Audio';
  static icon = MusicIcon;

  @field file = linksTo(() => AudioDef);

  // Back-compat shims. Player components read these names directly; the data
  // now flows from the linked AudioDef instead of being stored on this field.
  @field url = contains(StringField, {
    computeVia: function (this: AudioField) {
      return this.file?.url ?? '';
    },
  });
  @field filename = contains(StringField, {
    computeVia: function (this: AudioField) {
      return this.file?.name ?? '';
    },
  });
  @field mimeType = contains(StringField, {
    computeVia: function (this: AudioField) {
      return this.file?.contentType ?? '';
    },
  });
  @field fileSize = contains(NumberField, {
    computeVia: function (this: AudioField) {
      return this.file?.contentSize ?? 0;
    },
  });
  @field duration = contains(NumberField, {
    computeVia: function (this: AudioField) {
      return this.file?.duration ?? 0;
    },
  });

  // Optional metadata
  @field cardTitle = contains(StringField);
  @field artist = contains(StringField);
  @field waveformData = contains(StringField); // JSON array of heights

  // User interaction data (optional)
  @field liked = contains(BooleanField);
  @field playCount = contains(NumberField);
  @field lastPlayed = contains(DateTimeField);

  // Trimming data (optional)
  @field trimStart = contains(NumberField);
  @field trimEnd = contains(NumberField);

  // Playback settings (optional)
  @field playbackRate = contains(NumberField); // 0.5 to 2.0
  @field loopEnabled = contains(BooleanField);
  @field loopStart = contains(NumberField); // Loop start time in seconds
  @field loopEnd = contains(NumberField); // Loop end time in seconds

  @field displayTitle = contains(StringField, {
    computeVia: function (this: AudioField) {
      return this.cardTitle || this.file?.name || 'Untitled Audio';
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get configuration(): AudioFieldConfiguration {
      return (this.args.configuration as AudioFieldConfiguration) || {};
    }

    get presentation(): AudioPresentationStyle {
      return this.configuration.presentation || 'default';
    }

    get options(): AudioFieldOptions {
      return this.configuration.options || {};
    }

    <template>
      {{#if @model.url}}
        <BaseAudioPlayer
          @model={{@model}}
          @options={{this.options}}
          as |player|
        >
          {{#if (eq this.presentation 'waveform-player')}}
            <WaveformPlayer @model={{@model}} @player={{player}} />

          {{else if (eq this.presentation 'mini-player')}}
            <MiniPlayer @model={{@model}} @player={{player}} />

          {{else if (eq this.presentation 'album-cover')}}
            <AlbumCoverPlayer @model={{@model}} @player={{player}} />

          {{else if (eq this.presentation 'trim-editor')}}
            <TrimEditor @model={{@model}} @player={{player}} />

          {{else if (eq this.presentation 'playlist-row')}}
            <PlaylistRow @model={{@model}} @player={{player}} />

          {{else}}
            <div class='audio-player' data-test-audio-embedded>
              <audio
                {{player.setupAudio}}
                src={{@model.url}}
                {{on 'play' player.handlePlay}}
                {{on 'pause' player.handlePause}}
                {{on 'timeupdate' player.handleTimeUpdateWithTrim}}
                {{on 'loadedmetadata' player.handleLoadedMetadata}}
              >
                <track kind='captions' />
              </audio>

              <div class='player-header'>
                <div class='audio-icon'>
                  <MusicIcon width='24' height='24' />
                </div>
                <div class='audio-info'>
                  <div
                    class='audio-title'
                    data-test-audio-title
                  >{{@model.displayTitle}}</div>
                  {{#if @model.artist}}
                    <div
                      class='audio-artist'
                      data-test-audio-artist
                    >{{@model.artist}}</div>
                  {{/if}}
                  <div class='audio-metadata' data-test-audio-metadata>
                    {{#if @model.fileSize}}
                      <span>{{player.formatFileSize @model.fileSize}}</span>
                    {{/if}}
                    {{#if (and @model.fileSize player.audioDuration)}}
                      <span> • </span>
                    {{/if}}
                    {{#if player.displayDuration}}
                      <span>{{player.formatTime player.displayDuration}}</span>
                    {{/if}}
                  </div>
                </div>

                <Button
                  @kind='primary'
                  class='play-button'
                  data-test-audio-play-btn
                  {{on 'click' player.togglePlay}}
                >
                  {{#if player.isPlaying}}
                    <PauseIcon width='20' height='20' />
                  {{else}}
                    <PlayIcon width='20' height='20' />
                  {{/if}}
                </Button>
              </div>

              {{#if player.audioDuration}}
                <div class='player-controls' data-test-audio-controls>
                  <input
                    type='range'
                    min='0'
                    max={{player.displayDuration}}
                    value={{player.displayCurrentTime}}
                    {{on 'input' player.handleSeek}}
                    class='seek-bar'
                    data-test-audio-seek-bar
                    aria-label='Audio seek bar'
                  />
                  <div class='time-display'>
                    <span>{{player.formatTime player.displayCurrentTime}}</span>
                    <span>{{player.formatTime player.displayDuration}}</span>
                  </div>
                </div>
              {{/if}}

              {{#if this.options.showVolume}}
                <VolumeControl
                  @volume={{player.volume}}
                  @isMuted={{player.isMuted}}
                  @onVolumeChange={{player.handleVolumeChange}}
                  @onToggleMute={{player.toggleMute}}
                />
              {{/if}}

              {{#if
                (or this.options.showSpeedControl this.options.showLoopControl)
              }}
                <div
                  class='advanced-controls'
                  data-test-audio-advanced-controls
                >
                  {{#if this.options.showSpeedControl}}
                    <label class='control-label' data-test-audio-speed-control>
                      <span>Speed:</span>
                      <div class='speed-select'>
                        <BoxelSelect
                          @selected={{hash
                            value=player.playbackRate
                            label=(concat player.playbackRate 'x')
                          }}
                          @options={{array
                            (hash value=0.5 label='0.5x')
                            (hash value=0.75 label='0.75x')
                            (hash value=1 label='1x')
                            (hash value=1.25 label='1.25x')
                            (hash value=1.5 label='1.5x')
                            (hash value=2 label='2x')
                          }}
                          @onChange={{player.handleSpeedChange}}
                          @placeholder='1x'
                          @matchTriggerWidth={{true}}
                          as |item|
                        >
                          {{item.label}}
                        </BoxelSelect>
                      </div>
                    </label>
                  {{/if}}

                  {{#if this.options.showLoopControl}}
                    <label
                      class='control-label checkbox-label'
                      data-test-audio-loop-control
                    >
                      <input
                        type='checkbox'
                        checked={{player.isLooping}}
                        {{on 'change' player.toggleLoop}}
                        class='loop-checkbox'
                        data-test-audio-loop-checkbox
                      />
                      Loop
                    </label>
                  {{/if}}
                </div>
              {{/if}}
            </div>
          {{/if}}
        </BaseAudioPlayer>
      {{else}}
        <div class='audio-placeholder' data-test-audio-placeholder>
          <svg
            viewBox='0 0 24 24'
            fill='none'
            stroke='currentColor'
            stroke-width='2'
          >
            <path d='M9 18V5l12-2v13' />
            <circle cx='6' cy='18' r='3' />
            <circle cx='18' cy='16' r='3' />
          </svg>
          <span>No audio file</span>
        </div>
      {{/if}}

      <style scoped>
        .audio-player {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
          padding: var(--boxel-sp);
          background: var(--boxel-light, #ffffff);
          border: 1px solid var(--boxel-border-color, #e5e7eb);
          border-radius: var(--boxel-border-radius, 0.5rem);
        }

        .player-header {
          display: flex;
          align-items: center;
          gap: 0.75rem;
        }

        .audio-icon {
          width: 3rem;
          height: 3rem;
          background: linear-gradient(
            135deg,
            var(--primary, #3b82f6),
            var(--accent, #60a5fa)
          );
          border-radius: var(--boxel-border-radius, 0.5rem);
          display: flex;
          align-items: center;
          justify-content: center;
          color: white;
          flex-shrink: 0;
        }

        .audio-icon svg {
          width: 1.5rem;
          height: 1.5rem;
        }

        .audio-info {
          flex: 1;
          min-width: 0;
        }

        .audio-title {
          font-weight: 600;
          font-size: 0.875rem;
          color: var(--foreground, #1f2937);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .audio-artist {
          font-size: 0.75rem;
          color: var(--muted-foreground, #6b7280);
          margin-top: 0.125rem;
        }

        .audio-metadata {
          font-size: 0.75rem;
          color: var(--muted-foreground, #6b7280);
          margin-top: 0.25rem;
        }

        .play-button {
          width: 2.5rem;
          height: 2.5rem;
          border-radius: 50%;
          flex-shrink: 0;
          background: var(--primary, #3b82f6) !important;
          color: white !important;
        }

        .play-button:hover {
          background: var(--accent, #60a5fa) !important;
        }

        .player-controls {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }

        .seek-bar {
          width: 100%;
          height: 0.25rem;
          background: var(--muted, #e5e7eb);
          border-radius: 0.125rem;
          appearance: none;
          cursor: pointer;
        }

        .seek-bar::-webkit-slider-thumb {
          appearance: none;
          width: 0.75rem;
          height: 0.75rem;
          background: var(--primary, #3b82f6);
          border-radius: 50%;
          cursor: pointer;
        }

        .seek-bar::-moz-range-thumb {
          width: 0.75rem;
          height: 0.75rem;
          background: var(--primary, #3b82f6);
          border-radius: 50%;
          cursor: pointer;
          border: none;
        }

        .time-display {
          display: flex;
          justify-content: space-between;
          font-size: 0.75rem;
          color: var(--muted-foreground, #6b7280);
        }

        .audio-placeholder {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          padding: 1rem;
          color: var(--muted-foreground, #6b7280);
          font-size: 0.875rem;
          font-style: italic;
          border: 1px dashed var(--border, #e5e7eb);
          border-radius: var(--radius, 0.5rem);
        }

        .audio-placeholder svg {
          width: 1.25rem;
          height: 1.25rem;
        }

        /* ²⁶ Advanced Controls Styles */
        .advanced-controls {
          display: flex;
          align-items: center;
          gap: 1rem;
          padding-top: 0.5rem;
          border-top: 1px solid var(--border, #e5e7eb);
        }

        .control-label {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          font-size: 0.875rem;
          font-weight: 500;
          color: var(--foreground, #1f2937);
        }

        .checkbox-label {
          cursor: pointer;
          user-select: none;
        }

        .loop-checkbox {
          width: 1rem;
          height: 1rem;
          cursor: pointer;
          accent-color: var(--primary, #3b82f6);
        }

        .speed-select {
          min-width: 128px;
        }

        .control-label {
          gap: 0.5rem;
        }

        .control-label span {
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      {{#if @model.url}}
        <span class='audio-atom' data-test-audio-atom>
          <svg
            viewBox='0 0 24 24'
            fill='none'
            stroke='currentColor'
            stroke-width='2'
          >
            <path d='M9 18V5l12-2v13' />
            <circle cx='6' cy='18' r='3' />
            <circle cx='18' cy='16' r='3' />
          </svg>
          {{@model.displayTitle}}
        </span>
      {{/if}}

      <style scoped>
        .audio-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.875rem;
          color: var(--foreground, #1f2937);
        }

        .audio-atom svg {
          width: 1rem;
          height: 1rem;
          color: var(--primary, #3b82f6);
        }
      </style>
    </template>
  };

  static fitted = AudioFieldFitted;

  static edit = AudioFieldEdit;
}
