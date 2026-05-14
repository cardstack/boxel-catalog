import {
  CardDef,
  Component,
  field,
  contains,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import TagIcon from '@cardstack/boxel-icons/tag';

export const GENRE_EMOJI: Record<string, string> = {
  POP: '🎤',
  CLASSICAL: '🎻',
  DANCE: '🪩',
  INDIE: '🎸',
  ROCK: '🤘',
};

interface GenreTheme {
  from: string;
  to: string;
  accent: string;
  accentDim: string;
  accentBorder: string;
  image: string;
}

const GENRE_THEME: Record<string, GenreTheme> = {
  POP: {
    from: '#be185d',
    to: '#7c3aed',
    accent: '#f472b6',
    accentDim: 'rgba(244,114,182,0.18)',
    accentBorder: 'rgba(244,114,182,0.40)',
    image:
      'https://images.pexels.com/photos/1105666/pexels-photo-1105666.jpeg?auto=compress&cs=tinysrgb&w=900',
  },
  CLASSICAL: {
    from: '#1e3a8a',
    to: '#78350f',
    accent: '#fbbf24',
    accentDim: 'rgba(251,191,36,0.18)',
    accentBorder: 'rgba(251,191,36,0.40)',
    image:
      'https://images.pexels.com/photos/164693/pexels-photo-164693.jpeg?auto=compress&cs=tinysrgb&w=900',
  },
  DANCE: {
    from: '#4c1d95',
    to: '#0c4a6e',
    accent: '#22d3ee',
    accentDim: 'rgba(34,211,238,0.18)',
    accentBorder: 'rgba(34,211,238,0.40)',
    image:
      'https://images.pexels.com/photos/1190297/pexels-photo-1190297.jpeg?auto=compress&cs=tinysrgb&w=900',
  },
  INDIE: {
    from: '#14532d',
    to: '#713f12',
    accent: '#86efac',
    accentDim: 'rgba(134,239,172,0.18)',
    accentBorder: 'rgba(134,239,172,0.40)',
    image:
      'https://images.pexels.com/photos/1407322/pexels-photo-1407322.jpeg?auto=compress&cs=tinysrgb&w=900',
  },
  ROCK: {
    from: '#7f1d1d',
    to: '#1c1917',
    accent: '#f87171',
    accentDim: 'rgba(248,113,113,0.18)',
    accentBorder: 'rgba(248,113,113,0.40)',
    image:
      'https://images.pexels.com/photos/96380/pexels-photo-96380.jpeg?auto=compress&cs=tinysrgb&w=900',
  },
};

const DEFAULT_THEME: GenreTheme = {
  from: '#1e1b4b',
  to: '#312e81',
  accent: '#818cf8',
  accentDim: 'rgba(129,140,248,0.18)',
  accentBorder: 'rgba(129,140,248,0.40)',
  image:
    'https://images.pexels.com/photos/167636/pexels-photo-167636.jpeg?auto=compress&cs=tinysrgb&w=900',
};

export class Genre extends CardDef {
  static displayName = 'Genre';
  static icon = TagIcon;

  @field name = contains(StringField);

  @field title = contains(StringField, {
    computeVia: function (this: Genre) {
      return this.name ?? '';
    },
  });

  /* ── isolated ── */
  static isolated = class Isolated extends Component<typeof Genre> {
    get emoji() {
      return GENRE_EMOJI[(this.args.model?.name ?? '').toUpperCase()] ?? '🎵';
    }
    get theme(): GenreTheme {
      return (
        GENRE_THEME[(this.args.model?.name ?? '').toUpperCase()] ??
        DEFAULT_THEME
      );
    }
    get name() {
      return this.args.model?.name ?? 'Unknown Genre';
    }

    get bgImage(): string {
      return (
        this.args.model?.cardInfo?.cardThumbnail?.url ||
        (this.args.model as any)?.cardInfo?.cardThumbnailURL ||
        this.theme.image
      );
    }

    <template>
      <div
        class='gi-root'
        style='--gi-from:{{this.theme.from}};--gi-to:{{this.theme.to}};--gi-accent:{{this.theme.accent}};--gi-accent-dim:{{this.theme.accentDim}};--gi-accent-border:{{this.theme.accentBorder}};--gi-image:url("{{this.bgImage}}");'
      >
        {{! Photo layer }}
        <div class='gi-photo'></div>
        {{! Dark gradient scrim }}
        <div class='gi-scrim'></div>
        {{! Colour tint }}
        <div class='gi-tint'></div>
        {{! Noise grain overlay }}
        <div class='gi-grain'></div>

        <div class='gi-content'>
          <div class='gi-eyebrow'>
            <div class='gi-eyebrow-dot'></div>
            <span>Music Genre</span>
          </div>

          <div class='gi-hero'>
            <div class='gi-emoji-ring'>
              <span class='gi-emoji'>{{this.emoji}}</span>
            </div>
            <h1 class='gi-name'>{{this.name}}</h1>
            <div class='gi-rule'></div>
          </div>

          <div class='gi-meta'>
            <div class='gi-tag'>
              <svg
                width='10'
                height='10'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              >
                <path
                  d='M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82z'
                />
                <line x1='7' y1='7' x2='7.01' y2='7' />
              </svg>
              Genre Tag
            </div>
            <div class='gi-tag'>
              <svg
                width='10'
                height='10'
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
              VP.net
            </div>
          </div>
        </div>
      </div>

      <style scoped>
        .gi-root {
          position: relative;
          width: 100%;
          height: 100%;
          min-height: 320px;
          display: flex;
          overflow: hidden;
          font-family:
            -apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', sans-serif;
        }

        .gi-photo {
          position: absolute;
          inset: 0;
          background-image: var(--gi-image);
          background-size: cover;
          background-position: center;
          transform: scale(1.04);
          filter: saturate(1.1);
        }

        .gi-scrim {
          position: absolute;
          inset: 0;
          background: linear-gradient(
            to top,
            rgba(0, 0, 0, 0.9) 0%,
            rgba(0, 0, 0, 0.55) 40%,
            rgba(0, 0, 0, 0.25) 100%
          );
        }

        .gi-tint {
          position: absolute;
          inset: 0;
          background: linear-gradient(
            135deg,
            var(--gi-from) 0%,
            var(--gi-to) 100%
          );
          opacity: 0.45;
          mix-blend-mode: color;
        }

        .gi-grain {
          position: absolute;
          inset: 0;
          opacity: 0.03;
          background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E");
          background-size: 200px;
          pointer-events: none;
        }

        .gi-content {
          position: relative;
          z-index: 1;
          width: 100%;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: space-between;
          padding: 2.5rem 2rem;
        }

        .gi-eyebrow {
          display: flex;
          align-items: center;
          gap: 7px;
          font-size: 11px;
          font-weight: 600;
          color: var(--gi-accent);
          text-transform: uppercase;
          letter-spacing: 0.14em;
        }

        .gi-eyebrow-dot {
          width: 6px;
          height: 6px;
          border-radius: 50%;
          background: var(--gi-accent);
          box-shadow:
            0 0 10px var(--gi-accent),
            0 0 20px var(--gi-accent-dim);
        }

        .gi-hero {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 1.25rem;
        }

        .gi-emoji-ring {
          width: clamp(80px, 18vw, 120px);
          height: clamp(80px, 18vw, 120px);
          border-radius: 50%;
          background: rgba(255, 255, 255, 0.08);
          border: 1px solid var(--gi-accent-border);
          backdrop-filter: blur(12px);
          display: flex;
          align-items: center;
          justify-content: center;
          box-shadow:
            0 0 0 6px rgba(255, 255, 255, 0.04),
            0 0 40px var(--gi-accent-dim),
            inset 0 1px 0 rgba(255, 255, 255, 0.15);
        }

        .gi-emoji {
          font-size: clamp(2.5rem, 6vw, 4rem);
          line-height: 1;
          filter: drop-shadow(0 2px 8px rgba(0, 0, 0, 0.5));
        }

        .gi-name {
          font-size: clamp(2.2rem, 7vw, 5rem);
          font-weight: 900;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: #ffffff;
          text-shadow:
            0 2px 4px rgba(0, 0, 0, 0.6),
            0 0 40px var(--gi-accent-dim);
          margin: 0;
          text-align: center;
        }

        .gi-rule {
          width: 64px;
          height: 3px;
          border-radius: 2px;
          background: linear-gradient(
            90deg,
            transparent,
            var(--gi-accent),
            transparent
          );
          box-shadow: 0 0 12px var(--gi-accent);
        }

        .gi-meta {
          display: flex;
          align-items: center;
          gap: 10px;
        }

        .gi-tag {
          display: flex;
          align-items: center;
          gap: 5px;
          padding: 6px 14px;
          border-radius: 20px;
          background: rgba(255, 255, 255, 0.08);
          border: 1px solid rgba(255, 255, 255, 0.14);
          font-size: 11px;
          font-weight: 600;
          color: rgba(255, 255, 255, 0.7);
          backdrop-filter: blur(8px);
        }
      </style>
    </template>
  };

  /* ── fitted ── */
  static fitted = class Fitted extends Component<typeof Genre> {
    get emoji() {
      return GENRE_EMOJI[(this.args.model?.name ?? '').toUpperCase()] ?? '🎵';
    }
    get theme(): GenreTheme {
      return (
        GENRE_THEME[(this.args.model?.name ?? '').toUpperCase()] ??
        DEFAULT_THEME
      );
    }
    get name() {
      return this.args.model?.name ?? 'Genre';
    }

    get bgImage(): string {
      return (
        this.args.model?.cardInfo?.cardThumbnail?.url ||
        (this.args.model as any)?.cardInfo?.cardThumbnailURL ||
        this.theme.image
      );
    }

    <template>
      <article
        class='gf'
        style='--gf-from:{{this.theme.from}};--gf-to:{{this.theme.to}};--gf-accent:{{this.theme.accent}};--gf-accent-dim:{{this.theme.accentDim}};--gf-accent-border:{{this.theme.accentBorder}};--gf-image:url("{{this.bgImage}}");'
      >
        {{! ══ BADGE ≤150 × <170 ══ }}
        <section class='badge'>
          <div class='badge-photo'></div>
          <div class='badge-scrim'></div>
          <div class='badge-inner'>
            <div class='badge-ring'>
              <span class='badge-emoji'>{{this.emoji}}</span>
            </div>
            <span class='badge-name'>{{this.name}}</span>
          </div>
        </section>

        {{! ══ STRIP >150 × <170 ══ }}
        <section class='strip'>
          <div class='strip-photo'></div>
          <div class='strip-scrim'></div>
          <div class='strip-inner'>
            <div class='strip-emoji-wrap'>{{this.emoji}}</div>
            <span class='strip-name'>{{this.name}}</span>
            <span class='strip-chip'>Genre</span>
          </div>
        </section>

        {{! ══ TILE <400 × ≥170 ══ }}
        <article class='tile'>
          <div class='tile-photo'></div>
          <div class='tile-scrim'></div>
          <div class='tile-tint'></div>
          <header class='tile-hd'>
            <div class='tile-brand'>
              <svg
                width='10'
                height='10'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              >
                <path
                  d='M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82z'
                />
                <line x1='7' y1='7' x2='7.01' y2='7' />
              </svg>
            </div>
            <span class='tile-eyebrow'>Music Genre</span>
          </header>
          <section class='tile-body'>
            <div class='tile-ring'>
              <span class='tile-emoji'>{{this.emoji}}</span>
            </div>
            <h2 class='tile-name'>{{this.name}}</h2>
            <div class='tile-rule'></div>
          </section>
        </article>

        {{! ══ CARD ≥400 × ≥170 ══ }}
        <article class='card'>
          <div class='card-left'>
            <div class='card-photo'></div>
            <div class='card-scrim'></div>
            <div class='card-tint'></div>
            <div class='card-ring'>
              <span class='card-emoji'>{{this.emoji}}</span>
            </div>
          </div>
          <div class='card-divider'></div>
          <section class='card-body'>
            <div class='card-icon-row'>
              <div class='card-brand-icon'>
                <svg
                  width='10'
                  height='10'
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2'
                >
                  <path
                    d='M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82z'
                  />
                  <line x1='7' y1='7' x2='7.01' y2='7' />
                </svg>
              </div>
              <span class='card-eyebrow'>Music Genre</span>
            </div>
            <h2 class='card-name'>{{this.name}}</h2>
            <div class='card-rule'></div>
            <div class='card-chips'>
              <span class='chip chip--accent'>VP.net</span>
              <span class='chip'>Tag</span>
            </div>
          </section>
        </article>
      </article>

      <style scoped>
        .gf {
          --c-text: #ffffff;
          --c-text-2: rgba(255, 255, 255, 0.8);
          --c-muted: rgba(255, 255, 255, 0.5);
          --c-border: rgba(255, 255, 255, 0.14);
          --c-surface: rgba(255, 255, 255, 0.08);
          width: 100%;
          height: 100%;
          font-family:
            -apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', sans-serif;
        }

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

        /* shared photo/scrim helpers */
        .badge-photo,
        .strip-photo,
        .tile-photo,
        .card-photo {
          position: absolute;
          inset: 0;
          background-image: var(--gf-image);
          background-size: cover;
          background-position: center;
        }
        .badge-scrim,
        .strip-scrim,
        .tile-scrim,
        .card-scrim {
          position: absolute;
          inset: 0;
          background: rgba(0, 0, 0, 0.52);
        }
        .tile-tint,
        .card-tint {
          position: absolute;
          inset: 0;
          background: linear-gradient(
            135deg,
            var(--gf-from) 0%,
            var(--gf-to) 100%
          );
          opacity: 0.38;
          mix-blend-mode: color;
        }

        /* ══ BADGE ══ */
        @container fitted-card (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            position: relative;
            align-items: stretch;
          }
        }

        .badge-inner {
          position: relative;
          z-index: 1;
          width: 100%;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 7px;
          padding: 12px 8px;
        }

        .badge-ring {
          width: 46px;
          height: 46px;
          border-radius: 50%;
          background: rgba(255, 255, 255, 0.1);
          border: 1px solid var(--gf-accent-border);
          backdrop-filter: blur(6px);
          display: flex;
          align-items: center;
          justify-content: center;
          box-shadow: 0 0 16px var(--gf-accent-dim);
        }

        .badge-emoji {
          font-size: 22px;
          line-height: 1;
        }

        .badge-name {
          font-size: 9px;
          font-weight: 700;
          color: var(--c-text-2);
          text-transform: uppercase;
          letter-spacing: 0.08em;
          text-align: center;
          text-shadow: 0 1px 3px rgba(0, 0, 0, 0.8);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          max-width: 100%;
        }

        /* ══ STRIP ══ */
        @container fitted-card (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            position: relative;
            align-items: stretch;
            border-left: 3px solid var(--gf-accent);
          }
        }

        .strip-inner {
          position: relative;
          z-index: 1;
          width: 100%;
          display: flex;
          align-items: center;
          gap: 10px;
          padding: 0 14px;
        }

        .strip-emoji-wrap {
          font-size: 22px;
          line-height: 1;
          flex-shrink: 0;
          filter: drop-shadow(0 1px 4px rgba(0, 0, 0, 0.6));
        }

        .strip-name {
          flex: 1;
          font-size: 14px;
          font-weight: 800;
          color: var(--c-text);
          text-transform: uppercase;
          letter-spacing: 0.06em;
          text-shadow: 0 1px 4px rgba(0, 0, 0, 0.7);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .strip-chip {
          flex-shrink: 0;
          font-size: 9px;
          font-weight: 700;
          color: var(--gf-accent);
          background: var(--gf-accent-dim);
          border: 1px solid var(--gf-accent-border);
          border-radius: 4px;
          padding: 3px 7px;
          white-space: nowrap;
          backdrop-filter: blur(4px);
        }

        /* ══ TILE ══ */
        @container fitted-card (max-width: 399px) and (min-height: 170px) {
          .tile {
            display: flex;
            flex-direction: column;
            position: relative;
          }
        }

        .tile-hd {
          position: relative;
          z-index: 1;
          display: flex;
          align-items: center;
          gap: 7px;
          padding: 9px 12px;
          border-bottom: 1px solid rgba(255, 255, 255, 0.12);
          flex-shrink: 0;
          background: rgba(0, 0, 0, 0.2);
          backdrop-filter: blur(8px);
        }

        .tile-brand {
          width: 20px;
          height: 20px;
          border-radius: 5px;
          background: var(--gf-accent-dim);
          border: 1px solid var(--gf-accent-border);
          display: flex;
          align-items: center;
          justify-content: center;
          color: var(--gf-accent);
          flex-shrink: 0;
        }

        .tile-eyebrow {
          font-size: 10px;
          font-weight: 600;
          color: rgba(255, 255, 255, 0.6);
          text-transform: uppercase;
          letter-spacing: 0.08em;
        }

        .tile-body {
          position: relative;
          z-index: 1;
          flex: 1;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 10px;
          padding: 12px;
        }

        .tile-ring {
          width: clamp(48px, 12cqh, 72px);
          height: clamp(48px, 12cqh, 72px);
          border-radius: 50%;
          background: rgba(255, 255, 255, 0.1);
          border: 1px solid var(--gf-accent-border);
          backdrop-filter: blur(8px);
          display: flex;
          align-items: center;
          justify-content: center;
          box-shadow: 0 0 24px var(--gf-accent-dim);
        }

        .tile-emoji {
          font-size: clamp(22px, 6cqh, 36px);
          line-height: 1;
        }

        .tile-name {
          font-size: clamp(14px, 4cqw, 22px);
          font-weight: 900;
          color: var(--c-text);
          text-transform: uppercase;
          letter-spacing: 0.1em;
          text-align: center;
          text-shadow: 0 2px 8px rgba(0, 0, 0, 0.7);
          margin: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          max-width: 100%;
        }

        .tile-rule {
          width: 40px;
          height: 2px;
          border-radius: 1px;
          background: linear-gradient(
            90deg,
            transparent,
            var(--gf-accent),
            transparent
          );
          box-shadow: 0 0 8px var(--gf-accent);
        }

        /* ══ CARD ══ */
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .card {
            display: flex;
            flex-direction: row;
          }
        }

        .card-left {
          width: 130px;
          flex-shrink: 0;
          position: relative;
          display: flex;
          align-items: center;
          justify-content: center;
          overflow: hidden;
        }

        .card-ring {
          position: relative;
          z-index: 1;
          width: clamp(52px, 9cqh, 68px);
          height: clamp(52px, 9cqh, 68px);
          border-radius: 50%;
          background: rgba(255, 255, 255, 0.1);
          border: 1px solid var(--gf-accent-border);
          backdrop-filter: blur(8px);
          display: flex;
          align-items: center;
          justify-content: center;
          box-shadow: 0 0 20px var(--gf-accent-dim);
        }

        .card-emoji {
          font-size: clamp(24px, 5cqh, 36px);
          line-height: 1;
        }

        .card-divider {
          width: 1px;
          background: rgba(255, 255, 255, 0.12);
          flex-shrink: 0;
        }

        .card-body {
          flex: 1;
          position: relative;
          display: flex;
          flex-direction: column;
          gap: 4px;
          padding: 16px 18px;
          min-width: 0;
          justify-content: center;
          background: linear-gradient(
            135deg,
            var(--gf-from) 0%,
            var(--gf-to) 100%
          );
        }

        .card-body::before {
          content: '';
          position: absolute;
          inset: 0;
          background-image: var(--gf-image);
          background-size: cover;
          background-position: center;
          opacity: 0.12;
        }

        .card-icon-row {
          position: relative;
          z-index: 1;
          display: flex;
          align-items: center;
          gap: 6px;
          margin-bottom: 2px;
        }

        .card-brand-icon {
          width: 18px;
          height: 18px;
          border-radius: 4px;
          background: var(--gf-accent-dim);
          border: 1px solid var(--gf-accent-border);
          display: flex;
          align-items: center;
          justify-content: center;
          color: var(--gf-accent);
          flex-shrink: 0;
        }

        .card-eyebrow {
          font-size: 10px;
          font-weight: 600;
          color: var(--c-muted);
          text-transform: uppercase;
          letter-spacing: 0.08em;
        }

        .card-name {
          position: relative;
          z-index: 1;
          font-size: 20px;
          font-weight: 900;
          color: var(--c-text);
          text-transform: uppercase;
          letter-spacing: 0.1em;
          text-shadow: 0 1px 6px rgba(0, 0, 0, 0.5);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          line-height: 1.1;
          margin: 0;
        }

        .card-rule {
          position: relative;
          z-index: 1;
          width: 32px;
          height: 2px;
          border-radius: 1px;
          background: linear-gradient(90deg, var(--gf-accent), transparent);
          box-shadow: 0 0 6px var(--gf-accent);
          margin: 2px 0;
        }

        .card-chips {
          position: relative;
          z-index: 1;
          display: flex;
          gap: 5px;
          flex-wrap: wrap;
        }

        .chip {
          font-size: 9px;
          font-weight: 600;
          color: var(--c-muted);
          background: rgba(255, 255, 255, 0.07);
          border: 1px solid rgba(255, 255, 255, 0.14);
          border-radius: 4px;
          padding: 2px 7px;
          white-space: nowrap;
        }

        .chip--accent {
          color: var(--gf-accent);
          background: var(--gf-accent-dim);
          border-color: var(--gf-accent-border);
        }
      </style>
    </template>
  };

  /* ── atom ── */
  static atom = class Atom extends Component<typeof Genre> {
    <template>{{@model.name}}</template>
  };
}
