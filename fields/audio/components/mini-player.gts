import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn, concat } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import { Button, IconButton } from '@cardstack/boxel-ui/components';
import PlayIcon from '@cardstack/boxel-icons/play';
import PauseIcon from '@cardstack/boxel-icons/pause';
import type { BaseAudioPlayer, AudioFieldModel } from './base-audio-player';

interface MiniPlayerSignature {
  Args: {
    model: AudioFieldModel;
    player: BaseAudioPlayer;
  };
}

export class MiniPlayer extends GlimmerComponent<MiniPlayerSignature> {
  <template>
    <div class='mini-player' data-test-mini-player>
      <audio
        {{@player.setupAudio}}
        src={{@model.url}}
        {{on 'play' @player.handlePlay}}
        {{on 'pause' @player.handlePause}}
        {{on 'timeupdate' @player.handleTimeUpdateWithTrim}}
        {{on 'loadedmetadata' @player.handleLoadedMetadata}}
      >
        <track kind='captions' />
      </audio>

      <IconButton
        @icon={{if @player.isPlaying PauseIcon PlayIcon}}
        @width='18px'
        @height='18px'
        class='mini-play-btn'
        {{on 'click' @player.togglePlay}}
        aria-label={{if @player.isPlaying 'Pause' 'Play'}}
      />

      <div class='mini-info'>
        <div class='mini-title'>{{@model.displayTitle}}</div>
        {{#if @model.artist}}
          <div class='mini-artist'>{{@model.artist}}</div>
        {{/if}}
      </div>

      <div class='mini-skip-controls'>
        <Button
          @kind='ghost'
          class='skip-btn'
          {{on 'click' (fn @player.skipTime -15)}}
        >
          <svg
            viewBox='0 0 24 24'
            fill='none'
            stroke='currentColor'
            stroke-width='2'
          >
            <path d='M11 19l-7-7 7-7M18 19l-7-7 7-7' />
          </svg>
          <span>15</span>
        </Button>
        <Button
          @kind='ghost'
          class='skip-btn'
          {{on 'click' (fn @player.skipTime 15)}}
        >
          <span>15</span>
          <svg
            viewBox='0 0 24 24'
            fill='none'
            stroke='currentColor'
            stroke-width='2'
          >
            <path d='M13 5l7 7-7 7M6 5l7 7-7 7' />
          </svg>
        </Button>
      </div>

      <div class='mini-time'>
        {{@player.formatTime @player.displayCurrentTime}}
        <span class='time-separator'>/</span>
        {{@player.formatTime @player.displayDuration}}
      </div>

      {{#if @player.audioDuration}}
        <div class='mini-progress-container'>
          <div
            class='mini-progress-bar'
            style={{htmlSafe (concat 'width: ' @player.progressPercentage '%')}}
          ></div>
        </div>
      {{/if}}
    </div>

    <style scoped>
      .mini-player {
        container-type: inline-size;
        position: relative;
        display: grid;
        grid-template-columns: auto 1fr auto auto;
        grid-template-areas: 'play info skip time';
        align-items: center;
        column-gap: var(--boxel-sp);
        row-gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp) var(--boxel-sp-lg) calc(var(--boxel-sp) + 4px);
        background: var(--boxel-light, #ffffff);
        border: 1px solid var(--boxel-border-color, #e5e7eb);
        border-radius: var(--boxel-border-radius, 0.5rem);
        min-height: 60px;
      }

      .mini-play-btn {
        --boxel-button-min-width: 0;
        --boxel-button-min-height: 0;
        --boxel-button-padding: 0;
        grid-area: play;
        width: 2.5rem;
        height: 2.5rem;
        border-radius: 50%;
        flex-shrink: 0;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        background: var(--primary, #3b82f6) !important;
        color: white !important;
      }

      .mini-play-btn:hover {
        background: var(--accent, #60a5fa) !important;
      }

      .mini-info {
        grid-area: info;
        min-width: 0;
      }

      .mini-title {
        font-weight: 600;
        font-size: 0.875rem;
        color: var(--foreground, #1f2937);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .mini-artist {
        font-size: 0.75rem;
        color: var(--muted-foreground, #6b7280);
        margin-top: 0.125rem;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .mini-skip-controls {
        grid-area: skip;
        display: flex;
        align-items: center;
        gap: 0.25rem;
        flex-shrink: 0;
      }

      .skip-btn {
        --boxel-button-min-width: 0;
        --boxel-button-min-height: 0;
        --boxel-button-padding: 0 0.25rem;
        height: 1.75rem;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 0.125rem;
        font-size: 0.625rem;
        font-weight: 600;
        color: var(--muted-foreground, #6b7280);
      }

      .skip-btn svg {
        width: 0.875rem;
        height: 0.875rem;
      }

      .skip-btn:hover {
        color: var(--foreground, #1f2937);
        background: var(--muted, #f3f4f6);
      }

      .mini-time {
        grid-area: time;
        font-size: 0.75rem;
        color: var(--muted-foreground, #6b7280);
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
        flex-shrink: 0;
      }

      /* Narrow: stack to two rows — [play | info | time] / [skip spans all] */
      @container (max-width: 420px) {
        .mini-player {
          grid-template-columns: auto 1fr auto;
          grid-template-areas:
            'play info time'
            'skip skip skip';
        }

        .mini-skip-controls {
          justify-self: center;
        }
      }

      /* Very narrow: drop skip controls inline, stack info under play */
      @container (max-width: 260px) {
        .mini-player {
          grid-template-columns: auto 1fr;
          grid-template-areas:
            'play info'
            'skip time';
        }

        .mini-skip-controls {
          justify-self: start;
        }

        .mini-time {
          justify-self: end;
        }
      }

      .time-separator {
        margin: 0 0.25rem;
      }

      .mini-progress-container {
        position: absolute;
        bottom: 0;
        left: 0;
        right: 0;
        height: 3px;
        background: var(--muted, #e5e7eb);
        border-radius: 0 0 var(--radius, 0.5rem) var(--radius, 0.5rem);
        overflow: hidden;
      }

      .mini-progress-bar {
        height: 100%;
        background: var(--primary, #3b82f6);
        transition: width 0.1s linear;
      }
    </style>
  </template>
}
