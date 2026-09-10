import { CardDef, Component, contains, field } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import UserIcon from '@cardstack/boxel-icons/user';

type PlayerModel = {
  cardTitle?: string | null;
  cardThumbnailURL?: string | null;
};

function getPlayerName(model: PlayerModel | undefined): string {
  return model?.cardTitle?.trim() || 'Unknown Player';
}

function getPlayerInitials(name: string): string {
  let parts = name
    .split(/\s+/)
    .map((part) => part.trim())
    .filter(Boolean);

  if (parts.length === 0) {
    return 'P';
  }

  return parts
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? '')
    .join('');
}

class AtomTemplate extends Component<typeof Player> {
  get playerName() {
    return getPlayerName(this.args.model);
  }

  get avatarUrl() {
    return this.args.model?.cardThumbnailURL ?? null;
  }

  get initials() {
    return getPlayerInitials(this.playerName);
  }

  <template>
    <div class='player-chip'>
      <div class='player-chip__avatar'>
        {{#if this.avatarUrl}}
          <img
            class='player-chip__image'
            src={{this.avatarUrl}}
            alt={{this.playerName}}
          />
        {{else}}
          <span class='player-chip__initials'>{{this.initials}}</span>
        {{/if}}
      </div>
      <span class='player-chip__name'>{{this.playerName}}</span>
    </div>

    <style scoped>
      .player-chip {
        display: inline-flex;
        align-items: center;
        gap: 0.5rem;
        max-width: 100%;
        min-height: 2rem;
        padding: 0.1875rem 0.7rem 0.1875rem 0.1875rem;
        border: 1px solid color-mix(in oklch, var(--accent) 32%, transparent);
        border-radius: 62.4375rem;
        background: linear-gradient(
          90deg,
          color-mix(in oklch, var(--card) 98%, transparent),
          color-mix(in oklch, var(--card) 96%, transparent)
        );
        color: var(--warning-ink);
        box-shadow:
          inset 0 0 0 1px color-mix(in oklch, var(--card) 6%, transparent),
          0 0.375rem 1rem
            color-mix(in oklch, var(--shadow-color) 28%, transparent);
      }

      .player-chip__avatar {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 1.625rem;
        height: 1.625rem;
        flex-shrink: 0;
        overflow: hidden;
        border-radius: 50%;
        background:
          radial-gradient(circle, var(--success) 0 42%, transparent 43%),
          repeating-conic-gradient(
            from 0deg,
            var(--warning) 0 11deg,
            var(--destructive) 11deg 22deg
          );
        color: var(--warning-ink);
        box-shadow:
          inset 0 0 0 1px color-mix(in oklch, var(--card) 18%, transparent),
          0 0 0 1px color-mix(in oklch, var(--shadow-color) 20%, transparent);
      }

      .player-chip__image {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }

      .player-chip__initials {
        font-size: 0.6875rem;
        font-weight: 800;
        line-height: 1;
        letter-spacing: 0.04em;
      }

      .player-chip__name {
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        font-size: 0.8125rem;
        font-weight: 700;
        line-height: 1.2;
      }
    </style>
  </template>
}

class FittedTemplate extends Component<typeof Player> {
  get playerName() {
    return getPlayerName(this.args.model);
  }

  get avatarUrl() {
    return this.args.model?.cardThumbnailURL ?? null;
  }

  get initials() {
    return getPlayerInitials(this.playerName);
  }

  <template>
    <article class='player-fitted'>
      <div class='player-fitted__badge badge'>
        <div class='player-fitted__avatar'>
          {{#if this.avatarUrl}}
            <img
              class='player-fitted__image'
              src={{this.avatarUrl}}
              alt={{this.playerName}}
            />
          {{else}}
            <span class='player-fitted__initials'>{{this.initials}}</span>
          {{/if}}
        </div>
      </div>

      <div class='player-fitted__strip strip'>
        <div class='player-fitted__avatar'>
          {{#if this.avatarUrl}}
            <img
              class='player-fitted__image'
              src={{this.avatarUrl}}
              alt={{this.playerName}}
            />
          {{else}}
            <span class='player-fitted__initials'>{{this.initials}}</span>
          {{/if}}
        </div>
        <div class='player-fitted__copy'>
          <h3 class='player-fitted__title'>{{this.playerName}}</h3>
        </div>
      </div>

      <div class='player-fitted__tile tile'>
        <div class='player-fitted__avatar player-fitted__avatar--large'>
          {{#if this.avatarUrl}}
            <img
              class='player-fitted__image'
              src={{this.avatarUrl}}
              alt={{this.playerName}}
            />
          {{else}}
            <span class='player-fitted__initials'>{{this.initials}}</span>
          {{/if}}
        </div>
        <div class='player-fitted__copy player-fitted__copy--centered'>
          <p class='player-fitted__eyebrow'>Blackjack player</p>
          <h3 class='player-fitted__title player-fitted__title--centered'>
            {{this.playerName}}
          </h3>
        </div>
      </div>

      <div class='player-fitted__card card'>
        <div class='player-fitted__avatar player-fitted__avatar--large'>
          {{#if this.avatarUrl}}
            <img
              class='player-fitted__image'
              src={{this.avatarUrl}}
              alt={{this.playerName}}
            />
          {{else}}
            <span class='player-fitted__initials'>{{this.initials}}</span>
          {{/if}}
        </div>
        <div class='player-fitted__copy player-fitted__copy--card'>
          <p class='player-fitted__eyebrow'>Blackjack player</p>
          <h3 class='player-fitted__title'>{{this.playerName}}</h3>
          <p class='player-fitted__summary'>
            Reusable player card for blackjack tables, outcomes, and game links.
          </p>
        </div>
      </div>
    </article>

    <style scoped>
      .player-fitted {
        --vip-gold-glow: color-mix(in oklch, var(--accent) 45%, transparent);
        --chip-red: var(--destructive);

        width: 100%;
        height: 100%;
        color: var(--card-foreground);
      }

      .badge,
      .strip,
      .tile,
      .card {
        display: none;
        position: relative;
        width: 100%;
        height: 100%;
        box-sizing: border-box;
        overflow: hidden;
        border: 1px solid var(--vip-gold-glow);
        border-radius: 0.75rem;
        background: linear-gradient(
          180deg,
          color-mix(in oklch, var(--card) 96%, transparent),
          color-mix(in oklch, var(--card) 96%, transparent)
        );
        box-shadow: 0 0.625rem 1.5rem
          color-mix(in oklch, var(--shadow-color) 24%, transparent);
      }

      .badge::before,
      .strip::before,
      .tile::before,
      .card::before {
        content: '';
        position: absolute;
        inset: 0;
        opacity: 0.08;
        background-image:
          repeating-linear-gradient(
            45deg,
            var(--card) 0px,
            var(--card) 1px,
            transparent 1px,
            transparent 1.125rem
          ),
          repeating-linear-gradient(
            -45deg,
            var(--accent) 0px,
            var(--accent) 1px,
            transparent 1px,
            transparent 1.125rem
          );
        border-radius: inherit;
        pointer-events: none;
      }

      .player-fitted__badge,
      .player-fitted__tile,
      .player-fitted__card {
        align-items: center;
        justify-content: center;
      }

      .player-fitted__badge,
      .player-fitted__strip {
        padding: 0.25rem;
      }

      .player-fitted__tile,
      .player-fitted__card {
        padding: 0.75rem;
      }

      .player-fitted__strip,
      .player-fitted__card {
        gap: 0.75rem;
      }

      .player-fitted__strip {
        align-items: center;
      }

      .player-fitted__tile {
        flex-direction: column;
        gap: 0.5625rem;
        text-align: center;
      }

      .player-fitted__card {
        align-items: center;
      }

      .player-fitted__avatar {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 2.25rem;
        height: 2.25rem;
        flex-shrink: 0;
        overflow: hidden;
        border-radius: 50%;
        background:
          radial-gradient(circle, var(--success) 0 42%, transparent 43%),
          repeating-conic-gradient(
            from 0deg,
            var(--warning) 0 11deg,
            var(--chip-red) 11deg 22deg
          );
        color: var(--success-foreground);
        box-shadow: inset 0 0 0 1px
          color-mix(in oklch, var(--card) 18%, transparent);
      }

      .player-fitted__avatar--large {
        width: 4rem;
        height: 4rem;
        box-shadow:
          0 0 0 2px color-mix(in oklch, var(--accent) 60%, transparent),
          0 0 12px color-mix(in oklch, var(--accent) 30%, transparent),
          inset 0 0 0 1px color-mix(in oklch, var(--card) 18%, transparent);
      }

      .player-fitted__image {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }

      .player-fitted__initials {
        font-size: 0.875rem;
        font-weight: 700;
        line-height: 1.2;
        letter-spacing: 0.04em;
      }

      .player-fitted__copy {
        min-width: 0;
      }

      .player-fitted__copy--centered {
        text-align: center;
      }

      .player-fitted__copy--card {
        display: flex;
        flex: 1;
        min-width: 0;
        flex-direction: column;
        gap: 0.25rem;
      }

      .player-fitted__eyebrow {
        margin: 0;
        color: color-mix(in oklch, var(--warning-ink) 70%, transparent);
        font-size: 0.6875rem;
        font-weight: 600;
        line-height: 1;
        letter-spacing: 0.12em;
        text-transform: uppercase;
      }

      .player-fitted__title {
        margin: 0;
        min-width: 0;
        overflow: hidden;
        color: var(--card-foreground);
        text-overflow: ellipsis;
        white-space: nowrap;
        font-size: 0.875rem;
        font-weight: 700;
        line-height: 1.2;
      }

      .player-fitted__title--centered {
        white-space: normal;
        display: -webkit-box;
        -webkit-box-orient: vertical;
        -webkit-line-clamp: 2;
      }

      .player-fitted__summary {
        margin: 0;
        color: color-mix(in oklch, var(--warning-ink) 72%, transparent);
        font-size: 0.75rem;
        font-weight: 400;
        line-height: 1.35;
        display: -webkit-box;
        -webkit-box-orient: vertical;
        -webkit-line-clamp: 2;
        overflow: hidden;
      }

      @container fitted-card (max-width: 150px) and (max-height: 169px) {
        .badge {
          display: flex;
        }
      }

      @container fitted-card (min-width: 151px) and (max-height: 169px) {
        .strip {
          display: flex;
        }
      }

      @container fitted-card (max-width: 399px) and (min-height: 170px) {
        .tile {
          display: flex;
        }
      }

      @container fitted-card (min-width: 400px) and (min-height: 170px) {
        .card {
          display: flex;
        }
      }
    </style>
  </template>
}

class IsolatedTemplate extends Component<typeof Player> {
  get playerName() {
    return getPlayerName(this.args.model);
  }

  get avatarUrl() {
    return this.args.model?.cardThumbnailURL ?? null;
  }

  get initials() {
    return getPlayerInitials(this.playerName);
  }

  <template>
    <article class='player-isolated'>
      <div class='player-isolated__pattern' aria-hidden='true'></div>
      <div class='player-isolated__avatar'>
        {{#if this.avatarUrl}}
          <img
            class='player-isolated__image'
            src={{this.avatarUrl}}
            alt={{this.playerName}}
          />
        {{else}}
          <span class='player-isolated__initials'>{{this.initials}}</span>
        {{/if}}
      </div>
      <div class='player-isolated__copy'>
        <p class='player-isolated__eyebrow'>Blackjack Player</p>
        <h1 class='player-isolated__name'>{{this.playerName}}</h1>
      </div>
    </article>

    <style scoped>
      .player-isolated {
        --chip-red: var(--destructive);

        position: relative;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 1.25rem;
        width: 100%;
        min-height: 18rem;
        max-height: 26rem;
        height: 22rem;
        box-sizing: border-box;
        overflow: hidden;
        padding: 2rem 1.5rem;
        background: linear-gradient(
          180deg,
          color-mix(in oklch, var(--card) 98%, transparent),
          color-mix(in oklch, var(--card) 98%, transparent)
        );
        color: var(--card-foreground);
      }

      .player-isolated__pattern {
        position: absolute;
        inset: 0;
        opacity: 0.07;
        background-image:
          repeating-linear-gradient(
            45deg,
            var(--card) 0px,
            var(--card) 1px,
            transparent 1px,
            transparent 1.125rem
          ),
          repeating-linear-gradient(
            -45deg,
            var(--accent) 0px,
            var(--accent) 1px,
            transparent 1px,
            transparent 1.125rem
          );
        pointer-events: none;
      }

      .player-isolated__avatar {
        position: relative;
        display: flex;
        align-items: center;
        justify-content: center;
        width: 6rem;
        height: 6rem;
        flex-shrink: 0;
        overflow: hidden;
        border-radius: 50%;
        background:
          radial-gradient(circle, var(--success) 0 42%, transparent 43%),
          repeating-conic-gradient(
            from 0deg,
            var(--warning) 0 11deg,
            var(--chip-red) 11deg 22deg
          );
        color: var(--success-foreground);
        box-shadow:
          0 0 0 3px color-mix(in oklch, var(--accent) 65%, transparent),
          0 0 20px color-mix(in oklch, var(--accent) 25%, transparent),
          inset 0 0 0 1px color-mix(in oklch, var(--card) 18%, transparent);
      }

      .player-isolated__image {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }

      .player-isolated__initials {
        font-size: 1.75rem;
        font-weight: 800;
        line-height: 1;
        letter-spacing: 0.04em;
      }

      .player-isolated__copy {
        position: relative;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 0.375rem;
        text-align: center;
      }

      .player-isolated__eyebrow {
        margin: 0;
        color: color-mix(in oklch, var(--warning-ink) 65%, transparent);
        font-size: 0.6875rem;
        font-weight: 600;
        line-height: 1;
        letter-spacing: 0.14em;
        text-transform: uppercase;
      }

      .player-isolated__name {
        margin: 0;
        color: var(--card-foreground);
        font-size: 1.75rem;
        font-weight: 800;
        line-height: 1.15;
        letter-spacing: -0.01em;
      }
    </style>
  </template>
}

export class Player extends CardDef {
  static displayName = 'Player';
  static icon = UserIcon;

  @field cardThumbnailURL = contains(StringField, {
    computeVia(this: Player) {
      return (
        this.cardInfo?.cardThumbnail?.url ??
        this.cardInfo?.cardThumbnailURL ??
        ''
      );
    },
  });

  static atom = AtomTemplate;
  static fitted = FittedTemplate;
  static isolated = IsolatedTemplate;
  static embedded = IsolatedTemplate;
}
