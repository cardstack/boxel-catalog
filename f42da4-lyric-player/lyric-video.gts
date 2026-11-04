import {
  CardDef,
  Component,
  contains,
  field,
  linksTo,
  linksToMany,
} from '@cardstack/base/card-api';
import FileDef from '@cardstack/base/file-api';
import ImageDef from '@cardstack/base/image-file-def';
import StringField from '@cardstack/base/string';
import FilmIcon from '@cardstack/boxel-icons/film';

import { LyricPlayer } from './lyric-player';
import { clock, lyricFonts, type MixHint } from './mix-analysis';
import { SongVersion } from './song-version';
import type { Lang } from './song-clock';

/** the realm file among `files` whose name is `name` */
function fileUrl(
  files: { url?: string; id?: string }[] | undefined,
  name: string,
): string {
  const hit = (files ?? []).find((f) =>
    (f?.url ?? f?.id ?? '').endsWith(`/${name}`),
  );
  return hit?.url ?? hit?.id ?? '';
}

class Isolated extends Component<typeof LyricVideo> {
  audioUrl = (lang: Lang): string => this.version(lang)?.mix?.url ?? '';

  version = (lang: Lang): SongVersion | undefined =>
    (lang === 'ko' ? this.args.model.korean : this.args.model.english) ??
    undefined;

  /**
   * A file under this realm's `media/`. The photos, cutouts and fonts are
   * resolved next to the card rather than linked one by one; the mixes stay
   * linked, since the card is about them.
   */
  mediaUrl = (path: string): string => {
    // the linked mix sits at media/audio/en.m4a: its folder's parent is
    // media/, wherever this card is served from (a card URL or host mode's /)
    const mix = this.args.model.english?.mix?.url;
    return mix ? new URL(`../${path}`, mix).href : '';
  };

  /** each mix's waveform and tempo map, measured in Edit */
  hint = (lang: Lang): MixHint | undefined => this.version(lang)?.hint;

  /** each version's lyrics and word times, from its card */
  lyrics = (lang: Lang) => this.version(lang)?.songLyrics;

  get ready(): boolean {
    return Boolean(
      this.args.model.english?.mix?.url &&
      this.args.model.korean?.mix?.url &&
      this.args.model.english?.songLyrics &&
      this.args.model.korean?.songLyrics,
    );
  }

  <template>
    <article class='lyric-video'>
      {{#if this.ready}}
        <LyricPlayer
          @audioUrl={{this.audioUrl}}
          @hint={{this.hint}}
          @lyrics={{this.lyrics}}
          @mediaUrl={{this.mediaUrl}}
          @title={{@model.songTitle}}
          @artist={{@model.artist}}
          @credits={{@model.credits}}
          @publisher={{@model.publisher}}
        />
      {{else}}
        <p class='missing'>Link both language versions, each with its mix and
          lyrics, to play the video.</p>
      {{/if}}
    </article>
    <style scoped>
      .lyric-video {
        background: #0f0f10;
        color: #eef1f6;
        min-height: 100%;
        overflow-x: hidden;
      }
      header {
        padding: 20px 24px 32px;
        font-family: system-ui, sans-serif;
      }
      h1 {
        margin: 0 0 4px;
        font-size: 22px;
        letter-spacing: 0.04em;
      }
      header p,
      .missing {
        margin: 0;
        opacity: 0.7;
        font-size: 14px;
      }
      .missing {
        padding: 24px;
      }
    </style>
  </template>
}

/** the title's words the video sets in Instrument Serif italic: "just *ask* for *it*" */
const KEY_WORDS = new Set(['ask', 'it']);

/** what the small formats share: the cover, the stylized title, the versions */
class Face extends Component<typeof LyricVideo> {
  get cover(): string {
    const photos = (this.args.model.photos ?? []) as {
      url?: string;
      id?: string;
    }[];
    return fileUrl(photos, 'cover.jpg') || photos[0]?.url || '';
  }

  /** the linked mix, to find the realm's fonts next to it */
  get mixUrl(): string | undefined {
    return (
      this.args.model.english?.mix?.url ??
      this.args.model.korean?.mix?.url ??
      undefined
    );
  }

  get words(): { text: string; key: boolean }[] {
    return (this.args.model.songTitle ?? 'Untitled')
      .toLowerCase()
      .split(/\s+/)
      .filter(Boolean)
      .map((text) => ({ text, key: KEY_WORDS.has(text) }));
  }

  get versions(): { code: string; name: string; duration: string }[] {
    return [this.args.model.korean, this.args.model.english]
      .filter((v): v is SongVersion => Boolean(v))
      .map((v) => ({
        code: (v.language || v.name || '··').slice(0, 2).toUpperCase(),
        name: v.name ?? '',
        duration: clock(v.analysis?.duration),
      }));
  }
}

/**
 * The page's <head> when the card is published: a proper link preview (the
 * key art at 1200×630), the song's own icons, and a description that names
 * the writers.
 */
class Head extends Component<typeof LyricVideo> {
  /** a realm file as an absolute URL, wherever the card is served from */
  abs = (path: string): string => {
    const id = this.args.model.id;
    return id ? new URL(`../${path}`, id).href : '';
  };
  get title(): string {
    return this.args.model.songTitle ?? 'Just Ask For It';
  }
  get description(): string {
    return (
      this.args.model.cardDescription ??
      `Lyric video in 한국어 and English. ${this.args.model.credits ?? ''}`.trim()
    );
  }
  <template>
    {{! template-lint-disable no-forbidden-elements }}
    <title>{{this.title}}</title>
    <meta name='description' content={{this.description}} />
    <meta property='og:type' content='video.other' />
    <meta property='og:site_name' content={{this.title}} />
    <meta property='og:title' content={{this.title}} />
    <meta property='og:description' content={{this.description}} />
    <meta property='og:url' content={{@model.id}} />
    <meta property='og:image' content={{this.abs 'media/og/og-1200x630.jpg'}} />
    <meta property='og:image:width' content='1200' />
    <meta property='og:image:height' content='630' />
    <meta property='og:image:alt' content='just ask for it — the lyric video' />
    <meta name='twitter:card' content='summary_large_image' />
    <meta name='twitter:title' content={{this.title}} />
    <meta name='twitter:description' content={{this.description}} />
    <meta
      name='twitter:image'
      content={{this.abs 'media/og/og-1200x630.jpg'}}
    />
    <meta name='theme-color' content='#0f0f10' />
    <link rel='icon' href={{this.abs 'media/icons/icon-192.png'}} />
    <link rel='apple-touch-icon' href={{this.abs 'media/icons/icon-180.png'}} />
    <link rel='manifest' href={{this.abs 'manifest.json'}} />
  </template>
}

class Embedded extends Face {
  <template>
    <article class='lv-embedded' {{lyricFonts this.mixUrl}}>
      <div class='art'>
        {{#if this.cover}}
          <img src={{this.cover}} alt='Album cover' />
        {{/if}}
        <span class='label'>{{@model.songTitle}}</span>
      </div>
      <div class='body'>
        <p class='eyebrow'><span class='dot' aria-hidden='true'></span>Lyric
          video</p>
        <h3 class='title'>
          {{#each this.words as |w|}}
            {{#if w.key}}<em>{{w.text}}</em>{{else}}<span
              >{{w.text}}</span>{{/if}}
          {{/each}}
        </h3>
        {{#if this.versions.length}}
          <ul class='versions'>
            {{#each this.versions as |v|}}
              <li><span class='code'>{{v.code}}</span><span
                  class='vname'
                >{{v.name}}</span><span class='vdur'>{{v.duration}}</span></li>
            {{/each}}
          </ul>
        {{/if}}
        <p class='credits'>{{@model.credits}}{{#if @model.publisher}}<br />℗
            {{@model.publisher}}{{/if}}</p>
      </div>
    </article>
    <style scoped>
      .lv-embedded {
        --lyric:
          Pretendard, system-ui, -apple-system, 'Helvetica Neue', sans-serif;
        --serif: 'Instrument Serif', Georgia, 'Times New Roman', serif;
        --mono: 'Martian Mono', ui-monospace, 'SF Mono', Menlo, monospace;
        container: lv-embedded / inline-size;
        display: grid;
        grid-template-columns: auto minmax(0, 1fr);
        gap: 20px;
        padding: 16px;
        background: #d4dce7;
        color: #141418;
        font-family: var(--lyric);
      }
      .art {
        position: relative;
        width: 148px;
        aspect-ratio: 1;
        background: #c3ccd8;
        overflow: hidden;
      }
      img {
        display: block;
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .label {
        position: absolute;
        left: 8px;
        bottom: 8px;
        max-width: calc(100% - 16px);
        background: #141418;
        color: #fff;
        font: 500 10px/1 var(--lyric);
        letter-spacing: 0.02em;
        padding: 4px 6px 3px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .body {
        display: grid;
        align-content: start;
        gap: 10px;
        min-width: 0;
      }
      .eyebrow,
      .credits {
        margin: 0;
        font: 400 10px/1.5 var(--mono);
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: #4a505b;
      }
      .dot {
        display: inline-block;
        width: 7px;
        height: 7px;
        margin-right: 8px;
        border-radius: 50%;
        background: #ff2d4f;
        box-shadow: -2px 0 0 #19dbef;
        vertical-align: 0;
      }
      .title {
        margin: 0;
        display: flex;
        flex-wrap: wrap;
        align-items: baseline;
        column-gap: 0.26em;
        font: 200 38px/1 var(--lyric);
        letter-spacing: -0.01em;
      }
      .title em {
        font: italic 400 1.3em/0.8 var(--serif);
        letter-spacing: 0;
      }
      .versions {
        margin: 2px 0 0;
        padding: 0;
        list-style: none;
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
      }
      .versions li {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        padding: 0 10px 0 0;
        background: rgba(255, 255, 255, 0.55);
        font: 400 13px/1 var(--lyric);
      }
      .code {
        background: #141418;
        color: #fff;
        font: 500 10px/1 var(--lyric);
        letter-spacing: 0.04em;
        padding: 6px 6px 5px;
      }
      .vname {
        font-weight: 200;
        text-transform: lowercase;
      }
      .vdur {
        font: 400 10px/1 var(--mono);
        letter-spacing: 0.08em;
        font-variant-numeric: tabular-nums;
        color: #4a505b;
      }
      .credits {
        text-transform: none;
        letter-spacing: 0.04em;
      }
      @container lv-embedded (width < 420px) {
        .art {
          width: 96px;
        }
        .title {
          font-size: 28px;
        }
        .label {
          display: none;
        }
      }
    </style>
  </template>
}

class Fitted extends Face {
  <template>
    <article class='fit' {{lyricFonts this.mixUrl}}>
      <div class='art'>
        {{#if this.cover}}
          <img src={{this.cover}} alt='' />
        {{/if}}
        <span class='label'>{{@model.songTitle}}</span>
      </div>
      <div class='text'>
        <p class='eyebrow'><span class='dot' aria-hidden='true'></span>Lyric
          video</p>
        <h3 class='title'>
          {{#each this.words as |w|}}
            {{#if w.key}}<em>{{w.text}}</em>{{else}}<span
              >{{w.text}}</span>{{/if}}
          {{/each}}
        </h3>
        <p class='meta'>
          {{#each this.versions as |v|}}<span class='v'><b>{{v.code}}</b>
              {{v.duration}}</span>{{/each}}
        </p>
        <p class='credits'>{{@model.credits}}</p>
      </div>
    </article>
    <style scoped>
      .fit {
        --lyric:
          Pretendard, system-ui, -apple-system, 'Helvetica Neue', sans-serif;
        --serif: 'Instrument Serif', Georgia, 'Times New Roman', serif;
        --mono: 'Martian Mono', ui-monospace, 'SF Mono', Menlo, monospace;
        width: 100%;
        height: 100%;
        overflow: hidden;
        display: grid;
        grid-template: minmax(0, 1fr) / auto minmax(0, 1fr);
        background: #d4dce7;
        color: #141418;
        font-family: var(--lyric);
      }
      .art {
        position: relative;
        height: 100%;
        aspect-ratio: 1;
        min-height: 0;
        overflow: hidden;
        background: #c3ccd8;
      }
      img {
        display: block;
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .label {
        position: absolute;
        left: 8px;
        bottom: 8px;
        max-width: calc(100% - 16px);
        background: #141418;
        color: #fff;
        font: 500 10px/1 var(--lyric);
        letter-spacing: 0.02em;
        padding: 4px 6px 3px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .text {
        min-width: 0;
        min-height: 0;
        overflow: hidden;
        display: grid;
        grid-template-rows: auto auto auto minmax(0, 1fr);
        align-content: start;
        gap: 8px;
        padding: 14px 16px;
      }
      .eyebrow,
      .meta,
      .credits {
        margin: 0;
        font: 400 9px/1.4 var(--mono);
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: #4a505b;
        overflow: hidden;
      }
      .eyebrow,
      .meta {
        white-space: nowrap;
        text-overflow: ellipsis;
      }
      .credits {
        letter-spacing: 0.04em;
        text-transform: none;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        align-self: end;
      }
      .dot {
        display: inline-block;
        width: 6px;
        height: 6px;
        margin-right: 7px;
        border-radius: 50%;
        background: #ff2d4f;
        box-shadow: -2px 0 0 #19dbef;
        vertical-align: 0;
      }
      .title {
        margin: 0;
        display: flex;
        flex-wrap: wrap;
        align-items: baseline;
        column-gap: 0.26em;
        font: 200 30px/1 var(--lyric);
        letter-spacing: -0.01em;
        overflow: hidden;
      }
      .title em {
        font: italic 400 1.3em/0.8 var(--serif);
        letter-spacing: 0;
      }
      .meta .v + .v {
        margin-left: 12px;
      }
      .meta b {
        font-weight: 500;
        color: #141418;
      }

      /* tile, and tall cards: the cover on top */
      @container fitted-card (width <= 260px) and (height > 130px),
        fitted-card (width > 260px) and (height > 320px) {
        .fit {
          grid-template: minmax(0, 1fr) auto / minmax(0, 1fr);
        }
        .art {
          width: 100%;
          height: 100%;
          aspect-ratio: auto;
        }
        .text {
          grid-template-rows: auto auto auto;
          padding: 10px 12px 12px;
          gap: 6px;
        }
        .eyebrow {
          display: none;
        }
        .title {
          font-size: 21px;
          flex-wrap: nowrap;
          white-space: nowrap;
        }
        .credits {
          display: none;
        }
      }
      @container fitted-card (width > 260px) and (height > 320px) {
        .text {
          padding: 14px 16px 16px;
        }
        .eyebrow,
        .credits {
          display: block;
        }
        .title {
          font-size: 34px;
          flex-wrap: wrap;
          white-space: normal;
        }
      }
      /* strips and badges: one line of title beside a square thumbnail */
      @container fitted-card (height <= 130px) {
        .text {
          grid-template-rows: auto auto;
          align-content: center;
          gap: 5px;
          padding: 6px 12px;
        }
        .eyebrow,
        .credits {
          display: none;
        }
        .title {
          font-size: 22px;
          flex-wrap: nowrap;
          white-space: nowrap;
        }
        .label {
          display: none;
        }
      }
      @container fitted-card (height <= 130px) and (height > 80px) {
        .eyebrow {
          display: block;
        }
        .text {
          grid-template-rows: auto auto auto;
        }
      }
      @container fitted-card (height <= 50px) {
        .text {
          grid-template-rows: auto;
          padding: 0 10px;
        }
        .meta {
          display: none;
        }
        .title {
          font-size: 17px;
        }
      }
      @container fitted-card (height <= 80px) and (width <= 200px) {
        .meta {
          display: none;
        }
        .title {
          font-size: 16px;
        }
      }
    </style>
  </template>
}

/** a thumbnail of the cover, then "just *ask* for *it*" */
class Atom extends Face {
  <template>
    <span class='lv-atom' {{lyricFonts this.mixUrl}}>
      {{#if this.cover}}<img class='thumb' src={{this.cover}} alt='' />{{/if}}
      <span class='title'>
        {{#each this.words as |w|}}
          {{#if w.key}}<em>{{w.text}}</em>{{else}}<span>{{w.text}}</span>{{/if}}
        {{/each}}
      </span>
    </span>
    <style scoped>
      .lv-atom {
        display: inline-flex;
        align-items: center;
        gap: 0.4em;
        white-space: nowrap;
      }
      .thumb {
        width: 1.25em;
        height: 1.25em;
        object-fit: cover;
        flex: none;
      }
      .title {
        display: inline-flex;
        align-items: baseline;
        gap: 0.26em;
        font:
          200 1em/1 Pretendard,
          system-ui,
          sans-serif;
      }
      .title em {
        font:
          italic 400 1.2em/0.8 'Instrument Serif',
          Georgia,
          serif;
      }
    </style>
  </template>
}

export class LyricVideo extends CardDef {
  static displayName = 'Lyric Video';
  static icon = FilmIcon;
  // host mode shows it edge to edge, so phones get the whole player
  static prefersWideFormat = true;

  @field songTitle = contains(StringField);
  // the page's title (and a home-screen app's name) is the song's
  @field cardTitle = contains(StringField, {
    computeVia: function (this: LyricVideo) {
      return this.songTitle ?? 'Just Ask For It';
    },
  });
  @field artist = contains(StringField);
  /** "Written by …" */
  @field credits = contains(StringField);
  @field publisher = contains(StringField);
  /** each language version is its own card: its mix, tempo map and lyrics */
  @field korean = linksTo(SongVersion);
  @field english = linksTo(SongVersion);
  @field photos = linksToMany(ImageDef);
  @field fonts = linksToMany(FileDef);

  @field title = contains(StringField, {
    computeVia: function (this: LyricVideo) {
      return this.songTitle ? `${this.songTitle} — Lyric Video` : 'Lyric Video';
    },
  });

  static isolated = Isolated;
  static head = Head;
  static embedded = Embedded;
  static fitted = Fitted;
  static atom = Atom;
}
