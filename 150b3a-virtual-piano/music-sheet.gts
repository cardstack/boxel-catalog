import {
  CardDef,
  Component,
  field,
  contains,
  linksToMany,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import MarkdownField from 'https://cardstack.com/base/markdown';
import MusicIcon from '@cardstack/boxel-icons/music-2';
import { eq } from '@cardstack/boxel-ui/helpers';
import { htmlSafe } from '@ember/template';
import { Genre, GENRE_EMOJI } from './genre';

/* ── Difficulty helpers (VP.net scale 1–10) ──────────────────────────────
   1        → SUPER EASY
   2, 3, 4  → EASY
   5, 6, 7  → INTERMEDIATE
   8, 9, 10 → EXPERT
   ───────────────────────────────────────────────────────────────────────── */
function diffLabel(level: number | null | undefined): string {
  if (!level) return 'UNKNOWN';
  if (level === 1) return 'SUPER EASY';
  if (level <= 4) return 'EASY';
  if (level <= 7) return 'INTERMEDIATE';
  return 'EXPERT';
}

function diffClass(level: number | null | undefined): string {
  if (!level) return 'diff-unknown';
  if (level === 1) return 'diff-super-easy';
  if (level <= 4) return 'diff-easy';
  if (level <= 7) return 'diff-intermediate';
  return 'diff-expert';
}

export class MusicSheet extends CardDef {
  static displayName = 'Music Sheet';
  static icon = MusicIcon;

  @field songTitle = contains(StringField);
  @field artist = contains(StringField);
  /** Difficulty level on VP.net scale 1–10.
   *  1 = Super Easy, 2–4 = Easy, 5–7 = Intermediate, 8–10 = Expert */
  @field difficulty = contains(NumberField);
  /** VP.net notation string (Markdown field so multiline sheets render well).
   *  Format: space-separated groups, e.g. "t y [tu] - u i o p"
   *    single note: t   chord (simultaneous): [tu]   rest: -   phrase: | */
  @field notation = contains(MarkdownField);

  /** BPM — controls auto-play timing: beatMs = 60 000 / tempo */
  @field tempo = contains(NumberField);

  /** Genre tags — linked Genre cards (POP | CLASSICAL | DANCE | INDIE | ROCK) */
  @field genre = linksToMany(Genre);

  /** Semitone shift for playback transposition, e.g. -2 */
  @field transposition = contains(NumberField);

  @field title = contains(StringField, {
    computeVia: function (this: MusicSheet) {
      try {
        return this.songTitle || 'Untitled Song';
      } catch (e) {
        return 'Untitled Song';
      }
    },
  });

  /* ─── isolated ──────────────────────────────────────────────────────── */
  static isolated = class Isolated extends Component<typeof this> {
    get difficultyLabel() {
      return diffLabel(this.args.model?.difficulty);
    }

    get difficultyClass() {
      return diffClass(this.args.model?.difficulty);
    }

    get notationRaw(): string {
      return ((this.args.model?.notation ?? '') as string).trim();
    }

    get hasNotation() {
      return this.notationRaw.length > 0;
    }

    /** Split notation by | into phrases; each phrase has typed tokens */
    get phrasesWithTypes(): Array<{
      phraseNum: number;
      tokens: Array<{ token: string; type: string }>;
    }> {
      const raw = this.notationRaw;
      if (!raw) return [];
      return raw
        .split('|')
        .map((phrase: string, idx: number) => ({
          phraseNum: idx + 1,
          tokens: phrase
            .trim()
            .split(/\s+/)
            .filter((t: string) => t.length > 0)
            .map((t: string) => ({
              token: t,
              type: t === '-' ? 'rest' : t.startsWith('[') ? 'chord' : 'note',
            })),
        }))
        .filter((p) => p.tokens.length > 0);
    }

    get genreTags(): Array<{ emoji: string; name: string }> {
      const tags = (this.args.model?.genre ?? []) as Genre[];
      return tags
        .filter((g: Genre) => g.name)
        .map((g: Genre) => ({
          emoji: GENRE_EMOJI[g.name ?? ''] ?? '🎵',
          name: g.name ?? '',
        }));
    }

    get estimatedDuration(): string {
      const tempo = this.args.model?.tempo;
      if (!tempo) return '';
      const totalBeats = this.phrasesWithTypes.reduce(
        (sum, p) => sum + p.tokens.length,
        0,
      );
      if (!totalBeats) return '';
      const totalMs = (totalBeats * 60000) / tempo;
      const totalSec = Math.round(totalMs / 1000);
      const m = Math.floor(totalSec / 60);
      const s = totalSec % 60;
      return `${m}:${s.toString().padStart(2, '0')}`;
    }

    get heroStyle() {
      const url =
        this.args.model?.cardInfo?.cardThumbnail?.url ||
        this.args.model?.cardThumbnailURL;
      if (url) return htmlSafe(`background-image: url('${url}')`);
      return htmlSafe('');
    }

    get hasStats(): boolean {
      return (
        this.genreTags.length > 0 ||
        this.estimatedDuration.length > 0 ||
        !!this.args.model?.transposition
      );
    }

    <template>
      <div class='ms-app'>

        {{! ── Hero Banner with cover image ── }}
        <div class='ms-hero' style={{this.heroStyle}}>
          <div class='ms-hero-overlay'>
            {{! Decorative piano key silhouette }}
            <div class='ms-piano-keys' aria-hidden='true'>
              <span class='ms-wk'></span><span class='ms-wk'></span><span
                class='ms-wk'
              ></span><span class='ms-wk'></span><span
                class='ms-wk'
              ></span><span class='ms-wk'></span><span
                class='ms-wk'
              ></span><span class='ms-wk'></span><span
                class='ms-wk'
              ></span><span class='ms-wk'></span><span
                class='ms-wk'
              ></span><span class='ms-wk'></span><span
                class='ms-wk'
              ></span><span class='ms-wk'></span><span
                class='ms-wk'
              ></span><span class='ms-wk'></span>
            </div>
            <div class='ms-hero-content'>
              <h1 class='ms-title'>{{if
                  @model.songTitle
                  @model.songTitle
                  'Untitled Song'
                }}</h1>
              {{#if @model.artist}}
                <p class='ms-artist'>by
                  <em>{{@model.artist}}</em></p>
              {{/if}}
              <div class='ms-hero-chips'>
                <span class='ms-diff-pill {{this.difficultyClass}}'>
                  {{#if @model.difficulty}}
                    <span class='ms-diff-num'>{{@model.difficulty}}</span>
                  {{/if}}
                  {{this.difficultyLabel}}
                </span>
                {{#if @model.tempo}}
                  <span class='ms-bpm-chip'>♩ {{@model.tempo}} BPM</span>
                {{/if}}
              </div>
            </div>
          </div>
        </div>

        {{! ── Genre + stats strip ── }}
        {{#if this.hasStats}}
          <div class='ms-stats-bar'>
            {{#each this.genreTags as |tag|}}
              <span class='ms-genre-chip'>{{tag.emoji}} {{tag.name}}</span>
            {{/each}}
            {{#if this.estimatedDuration}}
              <span class='ms-stat-chip'>⏱ {{this.estimatedDuration}}</span>
            {{/if}}
            {{#if @model.transposition}}
              <span class='ms-stat-chip'>↕ {{@model.transposition}} st</span>
            {{/if}}
          </div>
        {{/if}}

        {{! ── Notation sheet ── }}
        {{#if this.hasNotation}}
          <section class='ms-notation-section'>
            <div class='ms-section-header'>
              <span class='ms-section-icon'>🎼</span>
              <span class='ms-section-title'>Keyboard Notation Sheet</span>
              <span class='ms-section-hint'>Type these keys on your keyboard</span>
            </div>
            <div class='ms-sheet'>
              {{#each this.phrasesWithTypes as |phrase|}}
                <div class='ms-phrase'>
                  <span class='ms-phrase-num'>{{phrase.phraseNum}}</span>
                  <div class='ms-tokens'>
                    {{#each phrase.tokens as |t|}}
                      <span
                        class='ms-token
                          {{if
                            (eq t.type "rest")
                            "ms-rest"
                            (if (eq t.type "chord") "ms-chord" "ms-note")
                          }}'
                      >{{t.token}}</span>
                    {{/each}}
                  </div>
                </div>
              {{/each}}
            </div>
          </section>
        {{else}}
          <div class='ms-empty'>
            <span class='ms-empty-icon'>🎹</span>
            <p>No notation added yet.</p>
          </div>
        {{/if}}

      </div>

      <style scoped>
        /* ── Design tokens ── */
        .ms-app {
          --c-orange: #ff8c42;
          --c-orange-dim: rgba(255, 140, 66, 0.15);
          --c-orange-border: rgba(255, 140, 66, 0.32);
          --c-bg: #0d0d1a;
          --c-surface: #13132a;
          --c-text: #f0f0ff;
          --c-text-2: rgba(240, 240, 255, 0.65);
          --c-muted: rgba(240, 240, 255, 0.32);
          --c-border: rgba(255, 255, 255, 0.07);

          background: var(--c-bg);
          color: var(--c-text);
          font-family: 'Inter', system-ui, sans-serif;
          min-height: 100%;
          display: flex;
          flex-direction: column;
          overflow-y: auto;
        }

        /* ── Hero ── */
        .ms-hero {
          position: relative;
          min-height: clamp(220px, 30vw, 320px);
          background-color: #1a1a2e;
          background-size: cover;
          background-position: center;
          overflow: hidden;
          flex-shrink: 0;
        }

        .ms-hero-overlay {
          position: absolute;
          inset: 0;
          background: linear-gradient(
            to bottom,
            rgba(13, 13, 26, 0.12) 0%,
            rgba(13, 13, 26, 0.6) 50%,
            rgba(13, 13, 26, 0.96) 100%
          );
          display: flex;
          flex-direction: column;
          justify-content: flex-end;
          padding: 1.75rem 2.25rem;
          gap: 1rem;
        }

        /* Decorative piano key strip */
        .ms-piano-keys {
          position: absolute;
          bottom: 0;
          left: 0;
          right: 0;
          height: 52px;
          display: flex;
          gap: 2px;
          align-items: flex-end;
          padding: 0 1.5rem;
          opacity: 0.1;
          pointer-events: none;
        }

        .ms-wk {
          flex: 1;
          height: 52px;
          background: #f5f0e8;
          border-radius: 0 0 4px 4px;
        }

        .ms-hero-content {
          position: relative;
          z-index: 1;
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }

        .ms-title {
          font-size: clamp(1.75rem, 5cqi, 3.5rem);
          font-weight: 900;
          color: var(--c-orange);
          margin: 0;
          line-height: 1.05;
          letter-spacing: -1px;
          text-transform: uppercase;
          text-shadow:
            0 2px 24px rgba(255, 140, 66, 0.5),
            0 0 60px rgba(255, 140, 66, 0.2);
        }

        .ms-artist {
          font-size: clamp(0.875rem, 2cqi, 1.125rem);
          color: var(--c-text-2);
          margin: 0;
        }

        .ms-artist em {
          font-style: italic;
          color: var(--c-text);
          font-weight: 500;
        }

        .ms-hero-chips {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          flex-wrap: wrap;
          margin-top: 0.375rem;
        }

        /* Difficulty pill */
        .ms-diff-pill {
          display: inline-flex;
          align-items: center;
          gap: 5px;
          padding: 5px 14px;
          border-radius: 20px;
          font-size: 10px;
          font-weight: 800;
          letter-spacing: 0.9px;
          text-transform: uppercase;
        }

        .ms-diff-num {
          font-size: 16px;
          font-weight: 900;
          line-height: 1;
        }

        .diff-super-easy {
          background: rgba(105, 240, 174, 0.15);
          color: #69f0ae;
          border: 1px solid rgba(105, 240, 174, 0.3);
        }
        .diff-easy {
          background: rgba(130, 177, 255, 0.15);
          color: #82b1ff;
          border: 1px solid rgba(130, 177, 255, 0.3);
        }
        .diff-intermediate {
          background: rgba(255, 204, 128, 0.15);
          color: #ffcc80;
          border: 1px solid rgba(255, 204, 128, 0.3);
        }
        .diff-expert {
          background: rgba(255, 138, 128, 0.15);
          color: #ff8a80;
          border: 1px solid rgba(255, 138, 128, 0.3);
        }
        .diff-unknown {
          background: rgba(255, 255, 255, 0.06);
          color: var(--c-muted);
          border: 1px solid var(--c-border);
        }

        .ms-bpm-chip {
          padding: 5px 12px;
          border-radius: 20px;
          font-size: 11px;
          font-weight: 600;
          background: rgba(255, 255, 255, 0.08);
          color: var(--c-text-2);
          border: 1px solid rgba(255, 255, 255, 0.12);
        }

        /* ── Stats bar ── */
        .ms-stats-bar {
          display: flex;
          flex-wrap: wrap;
          gap: 0.5rem;
          padding: 0.875rem 2.25rem;
          border-bottom: 1px solid var(--c-border);
        }

        .ms-genre-chip {
          display: inline-flex;
          align-items: center;
          gap: 5px;
          padding: 4px 12px;
          border-radius: 12px;
          font-size: 11px;
          font-weight: 700;
          background: var(--c-orange-dim);
          color: var(--c-orange);
          border: 1px solid var(--c-orange-border);
        }

        .ms-stat-chip {
          display: inline-flex;
          align-items: center;
          gap: 4px;
          padding: 4px 12px;
          border-radius: 12px;
          font-size: 11px;
          font-weight: 600;
          background: rgba(255, 255, 255, 0.04);
          color: var(--c-muted);
          border: 1px solid var(--c-border);
        }

        /* ── Notation section ── */
        .ms-notation-section {
          flex: 1;
          padding: 1.5rem 2.25rem;
          display: flex;
          flex-direction: column;
          gap: 1rem;
        }

        .ms-section-header {
          display: flex;
          align-items: center;
          gap: 0.625rem;
          padding-bottom: 0.75rem;
          border-bottom: 1px solid var(--c-border);
        }

        .ms-section-icon {
          font-size: 16px;
        }

        .ms-section-title {
          font-size: 11px;
          font-weight: 800;
          letter-spacing: 1px;
          color: var(--c-orange);
          text-transform: uppercase;
          flex: 1;
        }

        .ms-section-hint {
          font-size: 10px;
          color: var(--c-muted);
          font-style: italic;
        }

        .ms-sheet {
          display: flex;
          flex-direction: column;
          gap: 0.625rem;
          border-left: 3px solid var(--c-orange-border);
          padding-left: 1.25rem;
        }

        .ms-phrase {
          display: flex;
          align-items: flex-start;
          gap: 0.75rem;
        }

        .ms-phrase-num {
          font-size: 9px;
          font-weight: 700;
          color: var(--c-muted);
          letter-spacing: 0.5px;
          min-width: 16px;
          padding-top: 8px;
          text-align: right;
          font-variant-numeric: tabular-nums;
          flex-shrink: 0;
        }

        .ms-tokens {
          display: flex;
          flex-wrap: wrap;
          gap: 4px;
          flex: 1;
        }

        .ms-token {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          min-width: 30px;
          height: 30px;
          padding: 0 5px;
          border-radius: 5px;
          font-family: 'SF Mono', 'Fira Code', 'Cascadia Code', monospace;
          font-size: 12px;
          font-weight: 700;
        }

        .ms-note {
          background: rgba(255, 255, 255, 0.08);
          color: var(--c-text);
          border: 1px solid rgba(255, 255, 255, 0.14);
          box-shadow:
            0 1px 0 rgba(255, 255, 255, 0.06),
            inset 0 1px 0 rgba(255, 255, 255, 0.06);
        }

        .ms-chord {
          background: var(--c-orange-dim);
          color: var(--c-orange);
          border: 1px solid var(--c-orange-border);
          font-size: 11px;
          min-width: auto;
          padding: 0 8px;
        }

        .ms-rest {
          color: var(--c-muted);
          border: 1px dashed rgba(255, 255, 255, 0.1);
          font-size: 9px;
          opacity: 0.6;
        }

        /* ── Empty state ── */
        .ms-empty {
          flex: 1;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 0.75rem;
          color: var(--c-muted);
          padding: 3rem;
          text-align: center;
        }

        .ms-empty-icon {
          font-size: 2.5rem;
          opacity: 0.4;
          display: block;
        }

        .ms-empty p {
          margin: 0;
          font-size: 0.875rem;
        }
      </style>
    </template>
  };

  /* ─── embedded ──────────────────────────────────────────────────────── */
  static embedded = class Embedded extends Component<typeof this> {
    get difficultyLabel() {
      return diffLabel(this.args.model?.difficulty);
    }

    get difficultyClass() {
      return diffClass(this.args.model?.difficulty);
    }

    <template>
      <div class='song-embedded'>
        <svg
          class='music-icon'
          width='14'
          height='14'
          viewBox='0 0 24 24'
          fill='none'
          stroke='currentColor'
          stroke-width='2'
        ><path d='M9 18V5l12-2v13' /><circle cx='6' cy='18' r='3' /><circle
            cx='18'
            cy='16'
            r='3'
          /></svg>
        <div class='song-info'>
          <span class='song-name'>{{if
              @model.songTitle
              @model.songTitle
              'Untitled Song'
            }}</span>
          {{#if @model.artist}}
            <span class='song-artist'>{{@model.artist}}</span>
          {{/if}}
        </div>
        {{#if @model.tempo}}
          <span class='tempo-chip'>{{@model.tempo}} BPM</span>
        {{/if}}
        <span
          class='diff-badge {{this.difficultyClass}}'
        >{{this.difficultyLabel}}</span>
      </div>

      <style scoped>
        .song-embedded {
          display: flex;
          align-items: center;
          gap: 0.625rem;
          padding: 0.5rem 0.75rem;
          border-radius: 6px;
          background: rgba(255, 140, 66, 0.04);
          border: 1px solid rgba(255, 140, 66, 0.1);
        }

        .music-icon {
          color: #ff8c42;
          flex-shrink: 0;
        }

        .song-info {
          display: flex;
          flex-direction: column;
          gap: 1px;
          min-width: 0;
          flex: 1;
        }

        .song-name {
          font-weight: 600;
          font-size: 13px;
          color: #1a1a2e;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        .song-artist {
          font-size: 11px;
          color: #888;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        .diff-badge {
          padding: 2px 8px;
          border-radius: 12px;
          font-size: 9px;
          font-weight: 800;
          letter-spacing: 0.5px;
          white-space: nowrap;
          flex-shrink: 0;
          text-transform: uppercase;
        }

        .diff-super-easy {
          background: #e8f5e9;
          color: #2e7d32;
        }
        .diff-easy {
          background: #e3f2fd;
          color: #1565c0;
        }
        .diff-intermediate {
          background: #fff3e0;
          color: #e65100;
        }
        .diff-expert {
          background: #fce4ec;
          color: #c62828;
        }
        .diff-unknown {
          background: #f5f5f5;
          color: #757575;
        }

        .tempo-chip {
          padding: 2px 7px;
          border-radius: 10px;
          font-size: 9px;
          font-weight: 700;
          background: rgba(255, 140, 66, 0.12);
          color: #ff8c42;
          border: 1px solid rgba(255, 140, 66, 0.25);
          white-space: nowrap;
          flex-shrink: 0;
        }
      </style>
    </template>
  };

  /* ─── fitted ────────────────────────────────────────────────────────── */
  static fitted = class Fitted extends Component<typeof this> {
    get difficultyLabel() {
      return diffLabel(this.args.model?.difficulty);
    }

    get difficultyClass() {
      return diffClass(this.args.model?.difficulty);
    }

    get genreList() {
      const genres = this.args.model?.genre;
      if (!genres?.length) return '';
      return genres
        .slice(0, 2)
        .map((g: { name?: string }) => g.name ?? '')
        .filter(Boolean)
        .join(' · ');
    }

    get coverUrl(): string | null {
      return (
        (this.args.model as any)?.cardInfo?.cardThumbnail?.url ||
        (this.args.model as any)?.cardThumbnailURL ||
        null
      );
    }

    <template>
      <article class='ms-fitted'>

        {{! ══ BADGE ≤150 × <170 ══ }}
        <section class='badge'>
          <div class='badge-seal'>
            <svg
              width='22'
              height='22'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            >
              <path d='M9 18V5l12-2v13' /><circle cx='6' cy='18' r='3' /><circle
                cx='18'
                cy='16'
                r='3'
              />
            </svg>
          </div>
          <span class='badge-title'>{{if
              @model.songTitle
              @model.songTitle
              'Song'
            }}</span>
        </section>

        {{! ══ STRIP >150 × <170 ══ }}
        <section class='strip'>
          <div class='strip-icon'>
            <svg
              width='11'
              height='11'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            >
              <path d='M9 18V5l12-2v13' /><circle cx='6' cy='18' r='3' /><circle
                cx='18'
                cy='16'
                r='3'
              />
            </svg>
          </div>
          <span class='strip-title'>{{if
              @model.songTitle
              @model.songTitle
              'Untitled Song'
            }}</span>
          {{#if @model.artist}}<span
              class='strip-artist'
            >{{@model.artist}}</span>{{/if}}
          <span
            class='diff-badge {{this.difficultyClass}}'
          >{{this.difficultyLabel}}</span>
        </section>

        {{! ══ TILE <400 × ≥170 ══ }}
        <article class='tile'>
          <header class='tile-hd'>
            <div class='tile-brand-icon'>
              <svg
                width='11'
                height='11'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              >
                <path d='M9 18V5l12-2v13' /><circle
                  cx='6'
                  cy='18'
                  r='3'
                /><circle cx='18' cy='16' r='3' />
              </svg>
            </div>
            <span class='tile-eyebrow'>Sheet Music</span>
          </header>
          <section class='tile-body'>
            {{#if this.coverUrl}}
              <div class='tile-cover-wrap'>
                <img
                  src={{this.coverUrl}}
                  alt={{@model.songTitle}}
                  class='tile-cover'
                />
                <div class='tile-cover-info'>
                  <p class='tile-title tile-title--over'>{{if
                      @model.songTitle
                      @model.songTitle
                      'Untitled'
                    }}</p>
                  {{#if @model.artist}}<p
                      class='tile-artist tile-artist--over'
                    >{{@model.artist}}</p>{{/if}}
                  <span
                    class='diff-badge {{this.difficultyClass}} tile-diff-pill'
                  >{{this.difficultyLabel}}</span>
                </div>
              </div>
            {{else}}
              <div class='tile-diff-ring {{this.difficultyClass}}'>
                <svg
                  width='20'
                  height='20'
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2'
                >
                  <path d='M9 18V5l12-2v13' /><circle
                    cx='6'
                    cy='18'
                    r='3'
                  /><circle cx='18' cy='16' r='3' />
                </svg>
              </div>
              <p class='tile-title'>{{if
                  @model.songTitle
                  @model.songTitle
                  'Untitled'
                }}</p>
              {{#if @model.artist}}<p
                  class='tile-artist'
                >{{@model.artist}}</p>{{/if}}
              <span
                class='diff-badge {{this.difficultyClass}} tile-diff-pill'
              >{{this.difficultyLabel}}</span>
            {{/if}}
          </section>
          <footer class='tile-ft'>
            {{#if @model.tempo}}<span class='tempo-chip'>{{@model.tempo}}
                BPM</span>{{/if}}
            {{#if this.genreList}}<span
                class='genre-chip'
              >{{this.genreList}}</span>{{/if}}
          </footer>
        </article>

        {{! ══ CARD ≥400 × ≥170 ══ }}
        <article class='card'>
          <div class='card-left {{if this.coverUrl "card-left--cover"}}'>
            {{#if this.coverUrl}}
              <img
                src={{this.coverUrl}}
                alt={{@model.songTitle}}
                class='card-cover'
              />
              <div class='card-cover-badge'>
                <span
                  class='diff-badge {{this.difficultyClass}}'
                >{{this.difficultyLabel}}</span>
              </div>
            {{else}}
              <div class='card-diff-ring {{this.difficultyClass}}'>
                <svg
                  width='22'
                  height='22'
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2'
                >
                  <path d='M9 18V5l12-2v13' /><circle
                    cx='6'
                    cy='18'
                    r='3'
                  /><circle cx='18' cy='16' r='3' />
                </svg>
              </div>
              <span
                class='diff-badge {{this.difficultyClass}} card-diff-pill'
              >{{this.difficultyLabel}}</span>
              {{#if @model.tempo}}<span class='card-tempo'>{{@model.tempo}}
                  BPM</span>{{/if}}
            {{/if}}
          </div>
          <div class='card-divider'></div>
          <section class='card-body'>
            <div class='card-icon-row'>
              <div class='card-brand-icon'>
                <svg
                  width='11'
                  height='11'
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2'
                >
                  <path d='M9 18V5l12-2v13' /><circle
                    cx='6'
                    cy='18'
                    r='3'
                  /><circle cx='18' cy='16' r='3' />
                </svg>
              </div>
              <span class='card-eyebrow'>Sheet Music</span>
            </div>
            <h2 class='card-title'>{{if
                @model.songTitle
                @model.songTitle
                'Untitled Song'
              }}</h2>
            {{#if @model.artist}}<p
                class='card-artist'
              >{{@model.artist}}</p>{{/if}}
            {{#if this.genreList}}<p
                class='card-genre'
              >{{this.genreList}}</p>{{/if}}
          </section>
        </article>

      </article>

      <style scoped>
        .ms-fitted {
          /* ── Design tokens ── */
          --c-accent: #d97706;
          --c-accent-bg: #fffbeb;
          --c-accent-border: #fde68a;
          --c-bg: #f8fafc;
          --c-white: #ffffff;
          --c-text: #0f172a;
          --c-text-2: #1e293b;
          --c-muted: #64748b;
          --c-border: #e2e8f0;
          --c-shadow:
            0 1px 3px rgba(0, 0, 0, 0.07), 0 1px 2px rgba(0, 0, 0, 0.04);
          /* difficulty colours */
          --c-easy: #10b981;
          --c-mid: #f59e0b;
          --c-hard: #ef4444;

          width: 100%;
          height: 100%;
          font-family:
            -apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', sans-serif;
        }

        /* ── All sub-formats hidden by default ── */
        .badge,
        .strip,
        .tile,
        .card {
          display: none;
          width: 100%;
          height: 100%;
          box-sizing: border-box;
          overflow: hidden;
        }

        /* ══ BADGE ≤150 × <170 ══ */
        @container fitted-card (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            gap: 6px;
            background: var(--c-bg);
            padding: 10px 8px;
          }
        }

        .badge-seal {
          width: 44px;
          height: 44px;
          border-radius: 50%;
          background: linear-gradient(135deg, var(--c-accent) 0%, #b45309 100%);
          display: flex;
          align-items: center;
          justify-content: center;
          color: white;
          box-shadow: var(--c-shadow);
        }

        .badge-title {
          font-size: 9px;
          font-weight: 600;
          color: var(--c-muted);
          text-align: center;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          max-width: 100%;
          letter-spacing: 0.03em;
        }

        /* ══ STRIP >150 × <170 ══ */
        @container fitted-card (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            align-items: center;
            gap: 8px;
            padding: 0 14px;
            background: var(--c-white);
            border-left: 3px solid var(--c-accent);
          }
        }

        .strip-icon {
          flex-shrink: 0;
          width: 26px;
          height: 26px;
          border-radius: 50%;
          background: linear-gradient(135deg, var(--c-accent) 0%, #b45309 100%);
          display: flex;
          align-items: center;
          justify-content: center;
          color: white;
        }

        .strip-title {
          flex: 1;
          font-size: 13px;
          font-weight: 600;
          color: var(--c-text);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .strip-artist {
          flex-shrink: 0;
          font-size: 10px;
          color: var(--c-muted);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          max-width: 80px;
        }

        /* ══ TILE <400 × ≥170 ══ */
        @container fitted-card (max-width: 399px) and (min-height: 170px) {
          .tile {
            display: flex;
            flex-direction: column;
            background: var(--c-white);
          }
        }

        .tile-hd {
          background: var(--c-white);
          border-bottom: 1px solid var(--c-border);
          padding: 9px 12px;
          display: flex;
          align-items: center;
          gap: 7px;
          flex-shrink: 0;
        }

        .tile-brand-icon {
          width: 20px;
          height: 20px;
          border-radius: 5px;
          background: linear-gradient(135deg, var(--c-accent) 0%, #b45309 100%);
          display: flex;
          align-items: center;
          justify-content: center;
          color: white;
          flex-shrink: 0;
        }

        .tile-eyebrow {
          font-size: 10px;
          font-weight: 600;
          color: var(--c-muted);
          text-transform: uppercase;
          letter-spacing: 0.06em;
        }

        .tile-body {
          flex: 1;
          background: var(--c-bg);
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 3px;
          padding: 10px 12px;
        }

        .tile-diff-ring {
          width: clamp(40px, 10cqh, 56px);
          height: clamp(40px, 10cqh, 56px);
          border-radius: 50%;
          background: linear-gradient(135deg, var(--c-accent) 0%, #b45309 100%);
          display: flex;
          align-items: center;
          justify-content: center;
          color: white;
          box-shadow: var(--c-shadow);
          margin-bottom: 2px;
        }

        .tile-diff-ring.diff-super-easy,
        .tile-diff-ring.diff-easy {
          background: linear-gradient(135deg, #10b981 0%, #059669 100%);
        }
        .tile-diff-ring.diff-intermediate {
          background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%);
        }
        .tile-diff-ring.diff-expert {
          background: linear-gradient(135deg, #ef4444 0%, #b91c1c 100%);
        }

        .tile-title {
          font-size: 12px;
          font-weight: 700;
          color: var(--c-text);
          text-align: center;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          max-width: 100%;
          margin: 0;
        }

        .tile-artist {
          font-size: 10px;
          color: var(--c-muted);
          margin: 0;
          text-align: center;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          max-width: 100%;
        }

        .tile-diff-pill {
          margin-top: 2px;
        }

        /* tile cover image */
        .tile-cover-wrap {
          position: relative;
          width: 100%;
          height: 100%;
          overflow: hidden;
        }

        .tile-cover {
          width: 100%;
          height: 100%;
          object-fit: cover;
          display: block;
        }

        .tile-cover-info {
          position: absolute;
          bottom: 0;
          left: 0;
          right: 0;
          padding: 8px 10px 6px;
          background: linear-gradient(
            to top,
            rgba(0, 0, 0, 0.82) 0%,
            rgba(0, 0, 0, 0) 100%
          );
          display: flex;
          flex-direction: column;
          gap: 3px;
        }

        .tile-title--over {
          color: #fff !important;
          text-shadow: 0 1px 3px rgba(0, 0, 0, 0.6);
        }

        .tile-artist--over {
          color: rgba(255, 255, 255, 0.75) !important;
        }

        .tile-ft {
          background: var(--c-white);
          border-top: 1px solid var(--c-border);
          padding: 5px 12px;
          display: flex;
          align-items: center;
          gap: 6px;
          flex-shrink: 0;
          justify-content: center;
        }

        /* ══ CARD ≥400 × ≥170 ══ */
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .card {
            display: flex;
            flex-direction: row;
            background: var(--c-white);
          }
        }

        .card-left {
          width: 110px;
          flex-shrink: 0;
          background: var(--c-bg);
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 5px;
          padding: 16px 10px;
        }

        .card-diff-ring {
          width: clamp(40px, 8cqh, 56px);
          height: clamp(40px, 8cqh, 56px);
          border-radius: 50%;
          background: linear-gradient(135deg, var(--c-accent) 0%, #b45309 100%);
          display: flex;
          align-items: center;
          justify-content: center;
          color: white;
          box-shadow: var(--c-shadow);
          margin-bottom: 2px;
        }

        .card-diff-ring.diff-super-easy,
        .card-diff-ring.diff-easy {
          background: linear-gradient(135deg, #10b981 0%, #059669 100%);
        }
        .card-diff-ring.diff-intermediate {
          background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%);
        }
        .card-diff-ring.diff-expert {
          background: linear-gradient(135deg, #ef4444 0%, #b91c1c 100%);
        }

        .card-diff-pill {
          font-size: 9px !important;
        }

        /* card cover image */
        .card-left--cover {
          padding: 0;
          overflow: hidden;
          position: relative;
        }

        .card-cover {
          width: 100%;
          height: 100%;
          object-fit: cover;
          display: block;
        }

        .card-cover-badge {
          position: absolute;
          bottom: 6px;
          left: 0;
          right: 0;
          display: flex;
          justify-content: center;
        }

        .card-tempo {
          font-size: 10px;
          font-weight: 600;
          color: var(--c-muted);
          letter-spacing: 0.02em;
        }

        .card-divider {
          width: 1px;
          background: var(--c-border);
          flex-shrink: 0;
          margin: 14px 0;
        }

        .card-body {
          flex: 1;
          display: flex;
          flex-direction: column;
          gap: 3px;
          padding: 14px 16px;
          min-width: 0;
          justify-content: center;
        }

        .card-icon-row {
          display: flex;
          align-items: center;
          gap: 6px;
          margin-bottom: 2px;
        }

        .card-brand-icon {
          width: 18px;
          height: 18px;
          border-radius: 4px;
          background: linear-gradient(135deg, var(--c-accent) 0%, #b45309 100%);
          display: flex;
          align-items: center;
          justify-content: center;
          color: white;
          flex-shrink: 0;
        }

        .card-eyebrow {
          font-size: 10px;
          font-weight: 600;
          color: var(--c-muted);
          text-transform: uppercase;
          letter-spacing: 0.06em;
        }

        .card-title {
          font-size: 15px;
          font-weight: 700;
          color: var(--c-text);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          line-height: 1.2;
          margin: 0;
        }

        .card-artist {
          font-size: 12px;
          color: var(--c-text-2);
          margin: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .card-genre {
          font-size: 10px;
          color: var(--c-muted);
          margin: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        /* ══ Shared chips & badges ══ */
        .diff-badge {
          padding: 2px 7px;
          border-radius: 10px;
          font-size: 9px;
          font-weight: 700;
          letter-spacing: 0.4px;
          white-space: nowrap;
          flex-shrink: 0;
          text-transform: uppercase;
        }

        .diff-super-easy {
          background: #d1fae5;
          color: #065f46;
        }
        .diff-easy {
          background: #d1fae5;
          color: #065f46;
        }
        .diff-intermediate {
          background: #fef3c7;
          color: #92400e;
        }
        .diff-expert {
          background: #fee2e2;
          color: #991b1b;
        }
        .diff-unknown {
          background: #f1f5f9;
          color: #64748b;
        }

        .tempo-chip {
          padding: 2px 6px;
          border-radius: 8px;
          font-size: 9px;
          font-weight: 700;
          background: var(--c-accent-bg);
          border: 1px solid var(--c-accent-border);
          color: var(--c-accent);
          white-space: nowrap;
          flex-shrink: 0;
        }

        .genre-chip {
          padding: 2px 6px;
          border-radius: 8px;
          font-size: 9px;
          font-weight: 600;
          background: var(--c-bg);
          border: 1px solid var(--c-border);
          color: var(--c-muted);
          white-space: nowrap;
          flex-shrink: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          max-width: 90px;
        }
      </style>
    </template>
  };
}
