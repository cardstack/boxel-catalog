import {
  CardDef,
  Component,
  field,
  contains,
  linksToMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import MarkdownField from '@cardstack/base/markdown';
import MusicIcon from '@cardstack/boxel-icons/music-2';
import { eq } from '@cardstack/boxel-ui/helpers';
import { htmlSafe } from '@ember/template';
import { Genre, GENRE_EMOJI } from './genre';
import { diffLabel, diffClass } from './utils/diff-helpers';

/* ── Difficulty helpers (VP.net scale 1–10) ──────────────────────────────
   1        → SUPER EASY
   2, 3, 4  → EASY
   5, 6, 7  → INTERMEDIATE
   8, 9, 10 → EXPERT
   ───────────────────────────────────────────────────────────────────────── */

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
  @field genre = linksToMany(Genre, { searchable: true });

  /** Semitone shift for playback transposition, e.g. -2 */
  @field transposition = contains(NumberField);

  @field title = contains(StringField, {
    computeVia: function (this: MusicSheet) {
      try {
        return this.songTitle || 'Untitled Song';
      } catch {
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
          --ms-warning-dim: color-mix(
            in oklch,
            var(--warning) 15%,
            transparent
          );
          --ms-warning-border: color-mix(
            in oklch,
            var(--warning) 32%,
            transparent
          );

          background-color: var(--card);
          color: var(--card-foreground);
          font-family: 'Inter', system-ui, sans-serif;
          min-height: 100%;
          display: flex;
          flex-direction: column;
          overflow-y: auto;
        }

        /* ── Hero ── */
        .ms-hero {
          position: relative;
          min-height: clamp(13.75rem, 30vw, 20rem);
          background-color: var(--card);
          color: var(--card-foreground);
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
            color-mix(in oklch, var(--card) 12%, transparent) 0%,
            color-mix(in oklch, var(--card) 60%, transparent) 50%,
            color-mix(in oklch, var(--card) 96%, transparent) 100%
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
          height: 3.25rem;
          display: flex;
          gap: 2px;
          align-items: flex-end;
          padding: 0 1.5rem;
          opacity: 0.1;
          pointer-events: none;
        }

        .ms-wk {
          flex: 1;
          height: 3.25rem;
          background-color: var(--card);
          color: var(--card-foreground);
          border-radius: 0 0 0.25rem 0.25rem;
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
          color: var(--warning-ink);
          margin: 0;
          line-height: 1.05;
          letter-spacing: -1px;
          text-transform: uppercase;
          text-shadow:
            0 2px 24px color-mix(in oklch, var(--warning) 50%, transparent),
            0 0 60px color-mix(in oklch, var(--warning) 20%, transparent);
        }

        .ms-artist {
          font-size: clamp(0.875rem, 2cqi, 1.125rem);
          color: var(--subtle-foreground);
          margin: 0;
        }

        .ms-artist em {
          font-style: italic;
          color: var(--card-foreground);
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
          gap: 0.3125rem;
          padding: 0.3125rem 0.875rem;
          border-radius: 1.25rem;
          font-size: 0.625rem;
          font-weight: 800;
          letter-spacing: 0.9px;
          text-transform: uppercase;
        }

        .ms-diff-num {
          font-size: 1rem;
          font-weight: 900;
          line-height: 1;
        }

        .diff-super-easy {
          background-color: color-mix(
            in oklch,
            var(--success) 15%,
            transparent
          );
          color: var(--success-ink);
          border: 1px solid color-mix(in oklch, var(--success) 30%, transparent);
        }
        .diff-easy {
          background-color: color-mix(
            in oklch,
            var(--primary) 15%,
            transparent
          );
          color: var(--primary-ink);
          border: 1px solid color-mix(in oklch, var(--primary) 30%, transparent);
        }
        .diff-intermediate {
          background-color: color-mix(
            in oklch,
            var(--warning) 15%,
            transparent
          );
          color: var(--warning-ink);
          border: 1px solid color-mix(in oklch, var(--warning) 30%, transparent);
        }
        .diff-expert {
          background-color: color-mix(
            in oklch,
            var(--destructive) 15%,
            transparent
          );
          color: var(--destructive-ink);
          border: 1px solid
            color-mix(in oklch, var(--destructive) 30%, transparent);
        }
        .diff-unknown {
          background-color: color-mix(in oklch, var(--card) 6%, transparent);
          color: var(--muted-foreground);
          border: 1px solid var(--border);
        }

        .ms-bpm-chip {
          padding: 0.3125rem 0.75rem;
          border-radius: 1.25rem;
          font-size: 0.6875rem;
          font-weight: 600;
          background-color: color-mix(in oklch, var(--card) 8%, transparent);
          color: var(--subtle-foreground);
          border: 1px solid color-mix(in oklch, var(--card) 12%, transparent);
        }

        /* ── Stats bar ── */
        .ms-stats-bar {
          display: flex;
          flex-wrap: wrap;
          gap: 0.5rem;
          padding: 0.875rem 2.25rem;
          border-bottom: 1px solid var(--border);
        }

        .ms-genre-chip {
          display: inline-flex;
          align-items: center;
          gap: 0.3125rem;
          padding: 0.25rem 0.75rem;
          border-radius: 0.75rem;
          font-size: 0.6875rem;
          font-weight: 700;
          background-color: var(--ms-warning-dim);
          color: var(--warning-ink);
          border: 1px solid var(--ms-warning-border);
        }

        .ms-stat-chip {
          display: inline-flex;
          align-items: center;
          gap: 0.25rem;
          padding: 0.25rem 0.75rem;
          border-radius: 0.75rem;
          font-size: 0.6875rem;
          font-weight: 600;
          background-color: color-mix(in oklch, var(--card) 4%, transparent);
          color: var(--muted-foreground);
          border: 1px solid var(--border);
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
          border-bottom: 1px solid var(--border);
        }

        .ms-section-icon {
          font-size: 1rem;
        }

        .ms-section-title {
          font-size: 0.6875rem;
          font-weight: 800;
          letter-spacing: 1px;
          color: var(--warning-ink);
          text-transform: uppercase;
          flex: 1;
        }

        .ms-section-hint {
          font-size: 0.625rem;
          color: var(--muted-foreground);
          font-style: italic;
        }

        .ms-sheet {
          display: flex;
          flex-direction: column;
          gap: 0.625rem;
          border-left: 3px solid var(--ms-warning-border);
          padding-left: 1.25rem;
        }

        .ms-phrase {
          display: flex;
          align-items: flex-start;
          gap: 0.75rem;
        }

        .ms-phrase-num {
          font-size: 0.5625rem;
          font-weight: 700;
          color: var(--muted-foreground);
          letter-spacing: 0.5px;
          min-width: 1rem;
          padding-top: 0.5rem;
          text-align: right;
          font-variant-numeric: tabular-nums;
          flex-shrink: 0;
        }

        .ms-tokens {
          display: flex;
          flex-wrap: wrap;
          gap: 0.25rem;
          flex: 1;
        }

        .ms-token {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          min-width: 1.875rem;
          height: 1.875rem;
          padding: 0 0.3125rem;
          border-radius: 0.3125rem;
          font-family: 'SF Mono', 'Fira Code', 'Cascadia Code', monospace;
          font-size: 0.75rem;
          font-weight: 700;
        }

        .ms-note {
          background-color: color-mix(in oklch, var(--card) 8%, transparent);
          color: var(--card-foreground);
          border: 1px solid color-mix(in oklch, var(--card) 14%, transparent);
          box-shadow:
            0 1px 0 color-mix(in oklch, var(--card) 6%, transparent),
            inset 0 1px 0 color-mix(in oklch, var(--card) 6%, transparent);
        }

        .ms-chord {
          background-color: var(--ms-warning-dim);
          color: var(--warning-ink);
          border: 1px solid var(--ms-warning-border);
          font-size: 0.6875rem;
          min-width: auto;
          padding: 0 0.5rem;
        }

        .ms-rest {
          color: var(--muted-foreground);
          border: 1px dashed color-mix(in oklch, var(--card) 10%, transparent);
          font-size: 0.5625rem;
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
          color: var(--muted-foreground);
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
          border-radius: 0.375rem;
          background-color: color-mix(in oklch, var(--card) 4%, transparent);
          border: 1px solid color-mix(in oklch, var(--border) 10%, transparent);
        }

        .music-icon {
          color: var(--warning-ink);
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
          font-size: 0.8125rem;
          color: var(--foreground);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        .song-artist {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        .diff-badge {
          padding: 2px 0.5rem;
          border-radius: 0.75rem;
          font-size: 0.5625rem;
          font-weight: 800;
          letter-spacing: 0.5px;
          white-space: nowrap;
          flex-shrink: 0;
          text-transform: uppercase;
        }

        .diff-super-easy {
          background-color: var(--card);
          color: var(--success-ink);
        }
        .diff-easy {
          background-color: var(--card);
          color: var(--primary-ink);
        }
        .diff-intermediate {
          background-color: var(--card);
          color: var(--warning-ink);
        }
        .diff-expert {
          background-color: var(--card);
          color: var(--destructive-ink);
        }
        .diff-unknown {
          background-color: var(--card);
          color: var(--muted-foreground);
        }

        .tempo-chip {
          padding: 2px 0.4375rem;
          border-radius: 0.625rem;
          font-size: 0.5625rem;
          font-weight: 700;
          background-color: color-mix(
            in oklch,
            var(--warning) 12%,
            transparent
          );
          color: var(--warning-ink);
          border: 1px solid color-mix(in oklch, var(--warning) 25%, transparent);
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
          --ms-shadow:
            0 1px 0.1875rem
              color-mix(in oklch, var(--foreground) 7%, transparent),
            0 1px 2px color-mix(in oklch, var(--foreground) 4%, transparent);
          /* difficulty colours */

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
            gap: 0.375rem;
            background-color: var(--card);
            padding: 0.625rem 0.5rem;
          }
        }

        .badge-seal {
          width: 2.75rem;
          height: 2.75rem;
          border-radius: 50%;
          background: linear-gradient(
            135deg,
            var(--warning) 0%,
            var(--warning) 100%
          );
          display: flex;
          align-items: center;
          justify-content: center;
          color: var(--card-foreground);
          box-shadow: var(--ms-shadow);
        }

        .badge-title {
          font-size: 0.5625rem;
          font-weight: 600;
          color: var(--muted-foreground);
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
            gap: 0.5rem;
            padding: 0 0.875rem;
            background-color: var(--card);
            color: var(--card-foreground);
            border-left: 3px solid var(--warning);
          }
        }

        .strip-icon {
          flex-shrink: 0;
          width: 1.625rem;
          height: 1.625rem;
          border-radius: 50%;
          background: linear-gradient(
            135deg,
            var(--warning) 0%,
            var(--warning) 100%
          );
          display: flex;
          align-items: center;
          justify-content: center;
          color: var(--card-foreground);
        }

        .strip-title {
          flex: 1;
          font-size: 0.8125rem;
          font-weight: 600;
          color: var(--card-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .strip-artist {
          flex-shrink: 0;
          font-size: 0.625rem;
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          max-width: 5rem;
        }

        /* ══ TILE <400 × ≥170 ══ */
        @container fitted-card (max-width: 399px) and (min-height: 170px) {
          .tile {
            display: flex;
            flex-direction: column;
            background-color: var(--card);
            color: var(--card-foreground);
          }
        }

        .tile-hd {
          background-color: var(--card);
          color: var(--card-foreground);
          border-bottom: 1px solid var(--border);
          padding: 0.5625rem 0.75rem;
          display: flex;
          align-items: center;
          gap: 0.4375rem;
          flex-shrink: 0;
        }

        .tile-brand-icon {
          width: 1.25rem;
          height: 1.25rem;
          border-radius: 0.3125rem;
          background: linear-gradient(
            135deg,
            var(--warning) 0%,
            var(--warning) 100%
          );
          display: flex;
          align-items: center;
          justify-content: center;
          color: var(--card-foreground);
          flex-shrink: 0;
        }

        .tile-eyebrow {
          font-size: 0.625rem;
          font-weight: 600;
          color: var(--muted-foreground);
          text-transform: uppercase;
          letter-spacing: 0.06em;
        }

        .tile-body {
          flex: 1;
          background-color: var(--card);
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 0.1875rem;
          padding: 0.625rem 0.75rem;
        }

        .tile-diff-ring {
          width: clamp(2.5rem, 10cqh, 3.5rem);
          height: clamp(2.5rem, 10cqh, 3.5rem);
          border-radius: 50%;
          background: linear-gradient(
            135deg,
            var(--warning) 0%,
            var(--warning) 100%
          );
          display: flex;
          align-items: center;
          justify-content: center;
          color: var(--card-foreground);
          box-shadow: var(--ms-shadow);
          margin-bottom: 2px;
        }

        .tile-diff-ring.diff-super-easy,
        .tile-diff-ring.diff-easy {
          background: linear-gradient(
            135deg,
            var(--success) 0%,
            var(--success) 100%
          );
        }
        .tile-diff-ring.diff-intermediate {
          background: linear-gradient(
            135deg,
            var(--warning) 0%,
            var(--warning) 100%
          );
        }
        .tile-diff-ring.diff-expert {
          background: linear-gradient(
            135deg,
            var(--destructive) 0%,
            var(--destructive) 100%
          );
        }

        .tile-title {
          font-size: 0.75rem;
          font-weight: 700;
          color: var(--card-foreground);
          text-align: center;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          max-width: 100%;
          margin: 0;
        }

        .tile-artist {
          font-size: 0.625rem;
          color: var(--muted-foreground);
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
          padding: 0.5rem 0.625rem 0.375rem;
          background: linear-gradient(
            to top,
            color-mix(in oklch, var(--foreground) 82%, transparent) 0%,
            color-mix(in oklch, var(--foreground) 0%, transparent) 100%
          );
          display: flex;
          flex-direction: column;
          gap: 0.1875rem;
        }

        .tile-title--over {
          color: var(--card-foreground) !important;
          text-shadow: 0 1px 3px
            color-mix(in oklch, var(--foreground) 60%, transparent);
        }

        .tile-artist--over {
          color: color-mix(
            in oklch,
            var(--card-foreground) 75%,
            transparent
          ) !important;
        }

        .tile-ft {
          background-color: var(--card);
          color: var(--card-foreground);
          border-top: 1px solid var(--border);
          padding: 0.3125rem 0.75rem;
          display: flex;
          align-items: center;
          gap: 0.375rem;
          flex-shrink: 0;
          justify-content: center;
        }

        /* ══ CARD ≥400 × ≥170 ══ */
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .card {
            display: flex;
            flex-direction: row;
            background-color: var(--card);
            color: var(--card-foreground);
          }
        }

        .card-left {
          width: 6.875rem;
          flex-shrink: 0;
          background-color: var(--card);
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 0.3125rem;
          padding: 1rem 0.625rem;
        }

        .card-diff-ring {
          width: clamp(2.5rem, 8cqh, 3.5rem);
          height: clamp(2.5rem, 8cqh, 3.5rem);
          border-radius: 50%;
          background: linear-gradient(
            135deg,
            var(--warning) 0%,
            var(--warning) 100%
          );
          display: flex;
          align-items: center;
          justify-content: center;
          color: var(--card-foreground);
          box-shadow: var(--ms-shadow);
          margin-bottom: 2px;
        }

        .card-diff-ring.diff-super-easy,
        .card-diff-ring.diff-easy {
          background: linear-gradient(
            135deg,
            var(--success) 0%,
            var(--success) 100%
          );
        }
        .card-diff-ring.diff-intermediate {
          background: linear-gradient(
            135deg,
            var(--warning) 0%,
            var(--warning) 100%
          );
        }
        .card-diff-ring.diff-expert {
          background: linear-gradient(
            135deg,
            var(--destructive) 0%,
            var(--destructive) 100%
          );
        }

        .card-diff-pill {
          font-size: 0.5625rem !important;
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
          bottom: 0.375rem;
          left: 0;
          right: 0;
          display: flex;
          justify-content: center;
        }

        .card-tempo {
          font-size: 0.625rem;
          font-weight: 600;
          color: var(--muted-foreground);
          letter-spacing: 0.02em;
        }

        .card-divider {
          width: 1px;
          background-color: var(--border);
          flex-shrink: 0;
          margin: 0.875rem 0;
        }

        .card-body {
          flex: 1;
          display: flex;
          flex-direction: column;
          gap: 0.1875rem;
          padding: 0.875rem 1rem;
          min-width: 0;
          justify-content: center;
        }

        .card-icon-row {
          display: flex;
          align-items: center;
          gap: 0.375rem;
          margin-bottom: 2px;
        }

        .card-brand-icon {
          width: 1.125rem;
          height: 1.125rem;
          border-radius: 0.25rem;
          background: linear-gradient(
            135deg,
            var(--warning) 0%,
            var(--warning) 100%
          );
          display: flex;
          align-items: center;
          justify-content: center;
          color: var(--card-foreground);
          flex-shrink: 0;
        }

        .card-eyebrow {
          font-size: 0.625rem;
          font-weight: 600;
          color: var(--muted-foreground);
          text-transform: uppercase;
          letter-spacing: 0.06em;
        }

        .card-title {
          font-size: 0.9375rem;
          font-weight: 700;
          color: var(--card-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          line-height: 1.2;
          margin: 0;
        }

        .card-artist {
          font-size: 0.75rem;
          color: var(--subtle-foreground);
          margin: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .card-genre {
          font-size: 0.625rem;
          color: var(--muted-foreground);
          margin: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        /* ══ Shared chips & badges ══ */
        .diff-badge {
          padding: 2px 0.4375rem;
          border-radius: 0.625rem;
          font-size: 0.5625rem;
          font-weight: 700;
          letter-spacing: 0.4px;
          white-space: nowrap;
          flex-shrink: 0;
          text-transform: uppercase;
        }

        .diff-super-easy {
          background-color: var(--success);
          color: var(--success-foreground);
        }
        .diff-easy {
          background-color: var(--success);
          color: var(--success-foreground);
        }
        .diff-intermediate {
          background-color: var(--warning);
          color: var(--warning-foreground);
        }
        .diff-expert {
          background-color: var(--card);
          color: var(--destructive-ink);
        }
        .diff-unknown {
          background-color: var(--card);
          color: var(--primary-ink);
        }

        .tempo-chip {
          padding: 2px 0.375rem;
          border-radius: 0.5rem;
          font-size: 0.5625rem;
          font-weight: 700;
          background-color: var(--card);
          border: 1px solid var(--warning);
          color: var(--warning-ink);
          white-space: nowrap;
          flex-shrink: 0;
        }

        .genre-chip {
          padding: 2px 0.375rem;
          border-radius: 0.5rem;
          font-size: 0.5625rem;
          font-weight: 600;
          background-color: var(--card);
          border: 1px solid var(--border);
          color: var(--muted-foreground);
          white-space: nowrap;
          flex-shrink: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          max-width: 5.625rem;
        }
      </style>
    </template>
  };
}
