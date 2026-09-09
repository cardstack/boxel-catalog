import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { concat } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import { Button } from '@cardstack/boxel-ui/components';
import PlayIcon from '@cardstack/boxel-icons/play';
import PauseIcon from '@cardstack/boxel-icons/pause';
import type { BaseAudioPlayer, AudioFieldModel } from './base-audio-player';

interface AlbumCoverPlayerSignature {
  Args: {
    model: AudioFieldModel;
    player: BaseAudioPlayer;
  };
}

export class AlbumCoverPlayer extends GlimmerComponent<AlbumCoverPlayerSignature> {
  <template>
    <div class='album-player' data-test-album-cover-player>
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

      <div class='album-cover'>
        <div class='cover-gradient'></div>
        <div class='cover-overlay'>
          <Button
            @kind='primary'
            class='album-play-btn'
            {{on 'click' @player.togglePlay}}
            aria-label={{if @player.isPlaying 'Pause album' 'Play album'}}
          >
            {{#if @player.isPlaying}}
              <PauseIcon width='40' height='40' />
            {{else}}
              <PlayIcon width='40' height='40' />
            {{/if}}
          </Button>
        </div>
      </div>

      <div class='album-info'>
        <div class='album-title'>{{@model.displayTitle}}</div>
        {{#if @model.artist}}
          <div class='album-artist'>{{@model.artist}}</div>
        {{/if}}

        {{#if @player.audioDuration}}
          <div class='album-progress'>
            <div class='album-progress-bar'>
              <div
                class='album-progress-fill'
                style={{htmlSafe
                  (concat 'width: ' @player.progressPercentage '%')
                }}
              ></div>
            </div>
            <div class='album-time'>
              {{@player.formatTime @player.displayCurrentTime}}
              <span>/</span>
              {{@player.formatTime @player.displayDuration}}
            </div>
          </div>
        {{/if}}
      </div>
    </div>

    <style scoped>
      .album-player {
        display: flex;
        flex-direction: column;
        background-color: var(--card);
        color: var(--card-foreground);
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius);
        overflow: hidden;
      }

      .album-cover {
        position: relative;
        width: 100%;
        aspect-ratio: 1;
        overflow: hidden;
      }

      .cover-gradient {
        width: 100%;
        height: 100%;
        background: linear-gradient(
          135deg,
          var(--card) 0%,
          var(--card) 50%,
          var(--primary) 100%
        );
      }

      .cover-overlay {
        position: absolute;
        inset: 0;
        background-color: color-mix(in oklch, var(--card) 20%, transparent);
        display: flex;
        align-items: center;
        justify-content: center;
        opacity: 0;
        transition: opacity 0.2s;
      }

      .album-player:hover .cover-overlay {
        opacity: 1;
      }

      .album-play-btn {
        --boxel-button-min-width: 0;
        --boxel-button-min-height: 0;
        --boxel-button-padding: 0;
        width: 5rem;
        height: 5rem;
        border-radius: 50%;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        background-color: var(--card) !important;
        color: var(--primary-ink) !important;
        box-shadow: 0 10px 25px -5px
          color-mix(in oklch, var(--foreground) 30%, transparent) !important;
        transition: all 0.2s;
      }

      .album-play-btn:hover {
        background-color: color-mix(
          in oklch,
          var(--card) 95%,
          transparent
        ) !important;
        transform: scale(1.05);
      }

      .album-info {
        padding: 1.25rem;
        display: flex;
        flex-direction: column;
        gap: 0.75rem;
      }

      .album-title {
        font-weight: 700;
        font-size: 1.125rem;
        color: var(--foreground);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .album-artist {
        font-size: 0.875rem;
        color: var(--muted-foreground);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        margin-top: -0.5rem;
      }

      .album-progress {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
      }

      .album-progress-bar {
        width: 100%;
        height: 0.375rem;
        background-color: var(--muted);
        color: var(--muted-foreground);
        border-radius: 0.1875rem;
        overflow: hidden;
      }

      .album-progress-fill {
        height: 100%;
        background-color: var(--primary);
        color: var(--primary-foreground);
        transition: width 0.1s linear;
      }

      .album-time {
        display: flex;
        justify-content: space-between;
        font-size: 0.75rem;
        color: var(--muted-foreground);
        font-variant-numeric: tabular-nums;
      }

      .album-time span {
        margin: 0 0.25rem;
      }
    </style>
  </template>
}
