import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import RecordGameResultCommand from './record-game-result';
import {
  GameResult,
  GameStatusField,
  PlayerOutcomeField,
  type GameResultStatusType,
} from './game-result';
import { Player } from './player';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { task } from 'ember-concurrency';
import type Owner from '@ember/owner';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { eq, not } from '@cardstack/boxel-ui/helpers';
import { Button } from '@cardstack/boxel-ui/components';
import ValidationSteps, { type ValidationStep } from './validation-steps';
import { codeRef, realmURL } from '@cardstack/runtime-common';
import { PlayingCardField, StatsField, normalizeStatistics } from './fields';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const here: string = import.meta.url;

class IsolatedTemplate extends Component<typeof Blackjack> {
  // Game state
  @tracked gameState!: string;
  @tracked gameMessage!: string;

  // Player data
  @tracked playerChips!: number;
  @tracked currentBet!: number;
  @tracked statistics = {
    wins: 0,
    losses: 0,
    earnings: 0,
  };

  // Card deck and hands
  @tracked deck: PlayingCardField[] = [];
  @tracked playerHand: PlayingCardField[] = [];
  @tracked dealerHand: PlayingCardField[] = [];

  // ─── Enhanced UI getters ───────────────────────────────────────────────────

  get isGameOver() {
    return this.gameState === 'gameOver';
  }

  get playerWon() {
    return this.isGameOver && this.determineGameOutcome() === 'Win';
  }

  get playerLost() {
    return this.isGameOver && this.determineGameOutcome() === 'Lose';
  }

  get isPush() {
    return this.isGameOver && this.determineGameOutcome() === 'Draw';
  }

  get outcomeClass() {
    if (this.playerWon) return 'bj-outcome--win';
    if (this.playerLost) return 'bj-outcome--lose';
    return 'bj-outcome--push';
  }

  get outcomeIcon() {
    if (this.playerWon) return '🏆';
    if (this.playerLost) return '💔';
    return '🤝';
  }

  get outcomeTitle() {
    if (!this.isGameOver) return '';
    if (this.gameMessage?.includes('Blackjack!')) return '🃏 BLACKJACK!';
    if (
      this.gameMessage?.includes('Bust!') &&
      !this.gameMessage?.includes('Dealer')
    )
      return '💥 BUST!';
    if (this.gameMessage?.includes('Dealer busts')) return '🎉 DEALER BUSTS!';
    if (this.playerWon) return '🏆 YOU WIN!';
    if (this.playerLost) return '😔 YOU LOSE';
    return '🤝 PUSH';
  }

  get dealerScoreHidden() {
    return this.dealerHand.some((c) => !c.faceUp);
  }

  get displayedDealerScore(): string | number {
    if (this.dealerScoreHidden) return '?';
    return this.calculatedDealerScore;
  }

  get playerBust() {
    return this.calculatedPlayerScore > 21;
  }

  get playerPerfect() {
    return this.calculatedPlayerScore === 21;
  }

  get chipEarnings() {
    const e = this.statistics?.earnings || 0;
    return e >= 0 ? `+${e}` : String(e);
  }

  get earningsPositive() {
    return (this.statistics?.earnings || 0) >= 0;
  }

  get statusClass() {
    if (this.playerWon) return 'bj-status--win';
    if (this.playerLost) return 'bj-status--lose';
    if (this.isPush) return 'bj-status--push';
    return '';
  }

  get playerScoreClass() {
    if (this.playerBust) return 'bj-score--bust';
    if (this.playerPerfect) return 'bj-score--perfect';
    return '';
  }

  // ─── Validation ────────────────────────────────────────────────────────────

  get gameCanStart() {
    return !!this.args.model.player && !!this.args.model.dealer;
  }

  get validationSteps(): ValidationStep[] {
    const steps: ValidationStep[] = [];
    const hasPlayer = !!this.args.model.player;
    const hasDealer = !!this.args.model.dealer;

    if (!hasPlayer) {
      steps.push({
        id: 'player',
        title: '1. Add Player:',
        message: 'Link a player card to start playing',
        status: 'incomplete',
      });
    } else {
      steps.push({
        id: 'player',
        title: '✓ Player Added:',
        message: 'Player card is linked',
        status: 'complete',
      });
    }

    if (!hasDealer) {
      steps.push({
        id: 'dealer',
        title: '2. Add Dealer:',
        message: 'Link a dealer card to manage the game',
        status: 'incomplete',
      });
    } else {
      steps.push({
        id: 'dealer',
        title: '✓ Dealer Added:',
        message: 'Dealer card is linked',
        status: 'complete',
      });
    }

    if (hasPlayer && hasDealer) {
      steps.push({
        id: 'ready',
        title: '✓ Ready to Play:',
        message: 'All requirements met — game is ready!',
        status: 'complete',
      });
    }

    return steps;
  }

  // ─── Deck & game logic (unchanged) ─────────────────────────────────────────

  suits = ['hearts', 'diamonds', 'clubs', 'spades'];
  values = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];

  constructor(owner: Owner, args: any) {
    super(owner, args);
    this.gameState = args.model.gameState;
    this.gameMessage = args.model.gameMessage;
    this.playerChips = args.model.playerChips || 5000;
    this.currentBet = args.model.currentBet || 100;
    this.statistics = normalizeStatistics(args.model.statistics);
    this.createDeck();
    this.shuffleDeck();

    if (args.model.playerHand.length > 0 || args.model.dealerHand.length > 0) {
      const playerCards: PlayingCardField[] = [];
      const dealerCards: PlayingCardField[] = [];

      this.args.model.playerHand?.forEach((card) => {
        playerCards.push(
          new PlayingCardField({
            suit: card.suit,
            value: card.value,
            faceUp: card.faceUp !== undefined ? card.faceUp : true,
          }),
        );
      });

      this.args.model.dealerHand?.forEach((card) => {
        dealerCards.push(
          new PlayingCardField({
            suit: card.suit,
            value: card.value,
            faceUp: card.faceUp !== undefined ? card.faceUp : true,
          }),
        );
      });

      this.playerHand = playerCards;
      this.dealerHand = dealerCards;

      if (this.gameState === 'betting') {
        this.gameMessage = 'Place your bet and deal';
      } else if (this.gameState === 'playerTurn') {
        this.gameMessage = 'Your turn. Hit or Stand?';
      } else if (this.gameState === 'dealerTurn') {
        this.gameMessage = "Dealer's turn.";
        if (this.dealerHand.length > 0 && !this.dealerHand[1].faceUp) {
          setTimeout(() => this.dealerPlay(), 1000);
        }
      }
    } else {
      this.initializeGame();
    }
  }

  initializeGame() {
    this.gameState = 'betting';
    this.gameMessage = 'Place your bet and deal';
    this.playerHand = [];
    this.dealerHand = [];
  }

  createDeck() {
    this.deck = [];
    for (let suit of this.suits) {
      for (let value of this.values) {
        this.deck.push(new PlayingCardField({ suit, value, faceUp: true }));
      }
    }
  }

  shuffleDeck() {
    for (let i = this.deck.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [this.deck[i], this.deck[j]] = [this.deck[j], this.deck[i]];
    }
  }

  drawCard(faceUp = true) {
    if (this.deck.length === 0) {
      this.createDeck();
      this.shuffleDeck();
    }
    const card = this.deck.pop();
    if (!card) throw new Error('No card to draw');
    card.faceUp = faceUp;
    return card;
  }

  calculateScore(hand: PlayingCardField[]) {
    let score = 0;
    let aces = 0;
    for (let card of hand) {
      if (!card.faceUp) continue;
      if (card.value === 'A') {
        aces += 1;
        score += 11;
      } else if (['K', 'Q', 'J'].includes(card.value)) {
        score += 10;
      } else {
        score += parseInt(card.value);
      }
    }
    while (score > 21 && aces > 0) {
      score -= 10;
      aces -= 1;
    }
    return score;
  }

  checkForBlackjack() {
    const playerHasBlackjack =
      this.calculatedPlayerScore === 21 && this.playerHand.length === 2;
    const dealerHasBlackjack =
      this.calculatedDealerScore === 21 && this.dealerHand.length === 2;
    if (!this.currentBet) throw new Error('Current bet is undefined');

    if (playerHasBlackjack && dealerHasBlackjack) {
      this.gameState = 'gameOver';
      this.gameMessage = 'Push! Both have Blackjack.';
      this.saveGameState();
      this.recordGameResult();
      return true;
    } else if (playerHasBlackjack) {
      this.gameState = 'gameOver';
      this.gameMessage = 'Blackjack! You win 1.5x your bet!';
      this.playerChips += this.currentBet * 1.5;
      this.statistics.wins += 1;
      this.statistics.earnings += this.currentBet * 1.5;
      this.saveGameState();
      this.recordGameResult();
      return true;
    } else if (dealerHasBlackjack) {
      this.gameState = 'gameOver';
      this.gameMessage = 'Dealer has Blackjack! You lose.';
      this.playerChips -= this.currentBet;
      this.statistics.losses += 1;
      this.statistics.earnings -= this.currentBet;
      this.saveGameState();
      this.recordGameResult();
      return true;
    }
    return false;
  }

  checkForBust() {
    if (this.calculatedPlayerScore > 21) {
      this.gameState = 'gameOver';
      this.gameMessage = 'Bust! You lose.';
      this.playerChips -= this.currentBet;
      this.statistics.losses += 1;
      this.statistics.earnings -= this.currentBet;
      this.saveGameState();
      this.recordGameResult();
      return true;
    }
    return false;
  }

  dealerPlay() {
    const newDealerHand = [...this.dealerHand];
    newDealerHand.forEach((card) => (card.faceUp = true));
    this.dealerHand = newDealerHand;

    while (this.calculatedDealerScore < 17) {
      this.dealerHand = [...this.dealerHand, this.drawCard()];
    }

    const playerScore = this.calculatedPlayerScore;
    const dealerScore = this.calculatedDealerScore;

    if (dealerScore > 21) {
      this.gameMessage = 'Dealer busts! You win!';
      this.playerChips += this.currentBet;
      this.statistics.wins += 1;
      this.statistics.earnings += this.currentBet;
    } else if (dealerScore > playerScore) {
      this.gameMessage = 'Dealer wins!';
      this.playerChips -= this.currentBet;
      this.statistics.losses += 1;
      this.statistics.earnings -= this.currentBet;
    } else if (dealerScore < playerScore) {
      this.gameMessage = 'You win!';
      this.playerChips += this.currentBet;
      this.statistics.wins += 1;
      this.statistics.earnings += this.currentBet;
    } else {
      this.gameMessage = "Push! It's a tie.";
    }

    this.gameState = 'gameOver';
    this.saveGameState();
    this.recordGameResult();
  }

  @action placeBet(amount: number) {
    if (this.gameState !== 'betting') return;
    if (amount > this.playerChips) return;
    this.currentBet = amount;
    this.gameMessage = `Bet set to ${amount} chips — ready to deal!`;
  }

  @action deal() {
    if (!this.gameCanStart || this.gameState !== 'betting') return;
    if (this.playerChips < this.currentBet) {
      this.gameMessage = 'Not enough chips to place this bet!';
      return;
    }
    this.playerHand = [];
    this.dealerHand = [];

    const p1 = this.drawCard();
    const d1 = this.drawCard();
    const p2 = this.drawCard();
    const d2 = this.drawCard(false);

    this.playerHand = [p1, p2];
    this.dealerHand = [d1, d2];

    if (this.checkForBlackjack()) return;
    this.gameState = 'playerTurn';
    this.gameMessage = 'Your turn — Hit or Stand?';
    this.saveGameState();
  }

  @action hit() {
    if (this.gameState !== 'playerTurn') return;
    const newCard = this.drawCard();
    this.playerHand = [...this.playerHand, newCard];
    if (this.checkForBust()) return;
    this.gameMessage = `Drew ${newCard.value} of ${newCard.suit} — Hit or Stand?`;
  }

  @action stand() {
    if (this.gameState !== 'playerTurn') return;
    this.gameState = 'dealerTurn';
    this.gameMessage = "Dealer's turn…";
    setTimeout(() => this.dealerPlay(), 1000);
  }

  @action doubleDown() {
    if (this.gameState !== 'playerTurn' || this.playerHand.length !== 2) return;
    if (this.playerChips < this.currentBet) return;
    this.currentBet *= 2;
    this.gameMessage = 'Double Down! One card, then standing.';
    const newCard = this.drawCard();
    this.playerHand = [...this.playerHand, newCard];
    if (this.checkForBust()) return;
    setTimeout(() => this.stand(), 1000);
  }

  @action newGame() {
    if (this.gameState !== 'gameOver') return;
    if (this.deck.length < 10) {
      this.createDeck();
      this.shuffleDeck();
    }
    this.gameState = 'betting';
    this.gameMessage = 'Place your bet and deal';
    this.playerHand = [];
    this.dealerHand = [];
    this.saveGameState();
  }

  determineGameOutcome(): 'Win' | 'Lose' | 'Draw' {
    if (
      this.gameMessage?.includes('You win') ||
      this.gameMessage?.includes('Blackjack!') ||
      this.gameMessage?.includes('Dealer busts')
    )
      return 'Win';
    if (
      this.gameMessage?.includes('You lose') ||
      this.gameMessage?.includes('Bust!') ||
      this.gameMessage?.includes('Dealer wins') ||
      this.gameMessage?.includes('Dealer has Blackjack')
    )
      return 'Lose';
    return 'Draw';
  }

  determineDealerOutcome(
    playerOutcome: GameResultStatusType,
  ): GameResultStatusType {
    if (playerOutcome === 'Win') return 'Lose';
    if (playerOutcome === 'Lose') return 'Win';
    return 'Draw';
  }

  get currentRealm() {
    return this.args.model[realmURL];
  }

  recordGameResult() {
    if (this.gameState !== 'gameOver') return;
    this._recordGameResult.perform();
  }

  _recordGameResult = task(async () => {
    const game = this.args.model;
    const createdAt = new Date();
    const blackjackRef = codeRef(here, './blackjack', 'Blackjack');
    const commandContext = this.args.context?.commandContext;
    if (!commandContext)
      throw new Error('Command context not available. Please try again.');

    const playerOutcome = this.determineGameOutcome();
    const playerGameResult = new GameResult({
      game,
      outcome: new PlayerOutcomeField({
        player: this.args.model.player,
        outcome: new GameStatusField({ label: playerOutcome }),
      }),
      createdAt,
      ref: blackjackRef,
    });

    const dealerOutcome = this.determineDealerOutcome(playerOutcome);
    const dealerGameResult = new GameResult({
      game,
      outcome: new PlayerOutcomeField({
        player: this.args.model.dealer,
        outcome: new GameStatusField({ label: dealerOutcome }),
      }),
      createdAt,
      ref: blackjackRef,
    });

    await Promise.all([
      new RecordGameResultCommand(commandContext).execute({
        card: playerGameResult,
        realm: this.currentRealm!.href,
      }),
      new RecordGameResultCommand(commandContext).execute({
        card: dealerGameResult,
        realm: this.currentRealm!.href,
      }),
    ]);
  });

  saveGameState() {
    this.args.model.playerChips = this.playerChips;
    this.args.model.currentBet = this.currentBet;
    this.args.model.gameState = this.gameState;
    this.args.model.gameMessage = this.gameMessage;
    this.args.model.statistics ??= new StatsField();
    this.args.model.statistics.wins = this.statistics.wins;
    this.args.model.statistics.losses = this.statistics.losses;
    this.args.model.statistics.earnings = this.statistics.earnings;
    this.args.model.playerHand = [];
    this.args.model.dealerHand = [];
    this.playerHand.forEach((card) => {
      this.args.model.playerHand?.push(
        new PlayingCardField({
          suit: card.suit,
          value: card.value,
          faceUp: card.faceUp !== undefined ? card.faceUp : true,
        }),
      );
    });
    this.dealerHand.forEach((card) => {
      this.args.model.dealerHand?.push(
        new PlayingCardField({
          suit: card.suit,
          value: card.value,
          faceUp: card.faceUp !== undefined ? card.faceUp : true,
        }),
      );
    });
  }

  get calculatedPlayerScore() {
    return this.calculateScore(this.playerHand);
  }
  get calculatedDealerScore() {
    return this.calculateScore(this.dealerHand);
  }

  <template>
    <div class='bj-table'>

      {{! ── Setup validation overlay ── }}
      {{#unless this.gameCanStart}}
        <div class='bj-validation-overlay'>
          <ValidationSteps
            @steps={{this.validationSteps}}
            @title='Setup Required'
            @description='Link a dealer and player card to begin playing.'
            class='bj-validation-steps'
            as |step|
          >
            <div class='bj-validation-step-body'>
              <span class='validation-step__message'>{{step.message}}</span>
              {{#if (eq step.id 'player')}}
                {{#if (eq step.status 'incomplete')}}
                  <@fields.player
                    @format='edit'
                    class='bj-link-editor bj-link-editor--player'
                  />
                {{/if}}
              {{/if}}
              {{#if (eq step.id 'dealer')}}
                {{#if (eq step.status 'incomplete')}}
                  <@fields.dealer
                    @format='edit'
                    class='bj-link-editor bj-link-editor--dealer'
                  />
                {{/if}}
              {{/if}}
            </div>
          </ValidationSteps>
        </div>
      {{/unless}}

      {{! ── Game-over outcome overlay ── }}
      {{#if this.isGameOver}}
        <div class='bj-outcome-overlay {{this.outcomeClass}}'>
          <div class='bj-outcome-icon'>{{this.outcomeIcon}}</div>
          <div class='bj-outcome-title'>{{this.outcomeTitle}}</div>
          <div class='bj-outcome-sub'>{{this.gameMessage}}</div>
          <Button
            @kind='text-only'
            @size='auto'
            class='bj-play-again-btn'
            {{on 'click' this.newGame}}
          >Play Again</Button>
        </div>
      {{/if}}

      <div class='bj-content'>

        {{! ── Header ── }}
        <div class='bj-header'>
          <div class='bj-casino-title'>
            <span class='bj-suit-accent'>♠</span>
            <span class='bj-title-text'>{{@model.casinoName}}
              Blackjack</span>
            <span class='bj-suit-accent'>♠</span>
          </div>
          <div class='bj-stats'>
            <div class='bj-stat'>
              <span class='bj-stat-label'>Wins</span>
              <span
                class='bj-stat-val bj-stat-val--wins'
              >{{this.statistics.wins}}</span>
            </div>
            <div class='bj-stat'>
              <span class='bj-stat-label'>Losses</span>
              <span
                class='bj-stat-val bj-stat-val--losses'
              >{{this.statistics.losses}}</span>
            </div>
            <div class='bj-stat'>
              <span class='bj-stat-label'>P / L</span>
              <span
                class='bj-stat-val
                  {{if
                    this.earningsPositive
                    "bj-stat-val--pos"
                    "bj-stat-val--neg"
                  }}'
              >{{this.chipEarnings}}</span>
            </div>
          </div>
        </div>

        {{! ── Felt play area ── }}
        <div class='bj-felt'>

          {{! Dealer zone }}
          <div class='bj-zone'>
            <div class='bj-zone-bar'>
              <@fields.dealer
                @format='atom'
                @displayContainer={{false}}
                class='bj-player-pill'
              />
              <div
                class='bj-score-badge
                  {{if this.dealerScoreHidden "bj-score-badge--hidden"}}'
              >{{this.displayedDealerScore}}</div>
            </div>
            <div class='bj-cards'>
              {{#each this.dealerHand as |card|}}
                <div class='bj-card {{if (not card.faceUp) "bj-card--back"}}'>
                  {{#if card.faceUp}}
                    <div
                      class='bj-card-corner bj-card-tl bj-suit-{{card.suit}}'
                    >
                      <div class='bj-cv'>{{card.value}}</div>
                      <div class='bj-cp'>
                        {{#if (eq card.suit 'hearts')}}♥{{/if}}
                        {{#if (eq card.suit 'diamonds')}}♦{{/if}}
                        {{#if (eq card.suit 'clubs')}}♣{{/if}}
                        {{#if (eq card.suit 'spades')}}♠{{/if}}
                      </div>
                    </div>
                    <div class='bj-card-center bj-suit-{{card.suit}}'>
                      {{#if (eq card.suit 'hearts')}}♥{{/if}}
                      {{#if (eq card.suit 'diamonds')}}♦{{/if}}
                      {{#if (eq card.suit 'clubs')}}♣{{/if}}
                      {{#if (eq card.suit 'spades')}}♠{{/if}}
                    </div>
                    <div
                      class='bj-card-corner bj-card-br bj-suit-{{card.suit}}'
                    >
                      <div class='bj-cv'>{{card.value}}</div>
                      <div class='bj-cp'>
                        {{#if (eq card.suit 'hearts')}}♥{{/if}}
                        {{#if (eq card.suit 'diamonds')}}♦{{/if}}
                        {{#if (eq card.suit 'clubs')}}♣{{/if}}
                        {{#if (eq card.suit 'spades')}}♠{{/if}}
                      </div>
                    </div>
                  {{/if}}
                </div>
              {{/each}}
            </div>
          </div>

          {{! Divider }}
          <div class='bj-divider'>
            <div class='bj-divider-line'></div>
            <div class='bj-divider-text'>BLACKJACK PAYS 3 TO 2</div>
            <div class='bj-divider-line'></div>
          </div>

          {{! Player zone }}
          <div class='bj-zone'>
            <div class='bj-zone-bar'>
              <@fields.player
                @format='atom'
                @displayContainer={{false}}
                class='bj-player-pill'
              />
              <div
                class='bj-score-badge {{this.playerScoreClass}}'
              >{{this.calculatedPlayerScore}}</div>
            </div>
            <div class='bj-cards'>
              {{#each this.playerHand as |card|}}
                <div class='bj-card'>
                  <div class='bj-card-corner bj-card-tl bj-suit-{{card.suit}}'>
                    <div class='bj-cv'>{{card.value}}</div>
                    <div class='bj-cp'>
                      {{#if (eq card.suit 'hearts')}}♥{{/if}}
                      {{#if (eq card.suit 'diamonds')}}♦{{/if}}
                      {{#if (eq card.suit 'clubs')}}♣{{/if}}
                      {{#if (eq card.suit 'spades')}}♠{{/if}}
                    </div>
                  </div>
                  <div class='bj-card-center bj-suit-{{card.suit}}'>
                    {{#if (eq card.suit 'hearts')}}♥{{/if}}
                    {{#if (eq card.suit 'diamonds')}}♦{{/if}}
                    {{#if (eq card.suit 'clubs')}}♣{{/if}}
                    {{#if (eq card.suit 'spades')}}♠{{/if}}
                  </div>
                  <div class='bj-card-corner bj-card-br bj-suit-{{card.suit}}'>
                    <div class='bj-cv'>{{card.value}}</div>
                    <div class='bj-cp'>
                      {{#if (eq card.suit 'hearts')}}♥{{/if}}
                      {{#if (eq card.suit 'diamonds')}}♦{{/if}}
                      {{#if (eq card.suit 'clubs')}}♣{{/if}}
                      {{#if (eq card.suit 'spades')}}♠{{/if}}
                    </div>
                  </div>
                </div>
              {{/each}}
            </div>
          </div>

        </div>{{! /bj-felt }}

        {{! ── Bottom controls ── }}
        <div class='bj-bottom'>

          {{! Status message }}
          <div class='bj-status {{this.statusClass}}'>{{this.gameMessage}}</div>

          {{! Bankroll row }}
          <div class='bj-bankroll'>
            <div class='bj-chips-pill'>
              <span class='bj-chips-icon'>🪙</span>
              <span class='bj-chips-num'>{{this.playerChips}}</span>
              <span class='bj-chips-lbl'>chips</span>
            </div>
            <div class='bj-bet-pill'>
              <span class='bj-bet-lbl'>BET</span>
              <span class='bj-bet-num'>{{this.currentBet}}</span>
            </div>
          </div>

          {{! Action controls }}
          <div class='bj-controls'>

            {{#if (eq this.gameState 'betting')}}
              <div class='bj-chip-row'>
                <Button
                  @kind='text-only'
                  @size='auto'
                  class='bj-chip bj-chip--red'
                  @disabled={{not this.gameCanStart}}
                  {{on 'click' (fn this.placeBet 5)}}
                >5</Button>
                <Button
                  @kind='text-only'
                  @size='auto'
                  class='bj-chip bj-chip--blue'
                  @disabled={{not this.gameCanStart}}
                  {{on 'click' (fn this.placeBet 20)}}
                >20</Button>
                <Button
                  @kind='text-only'
                  @size='auto'
                  class='bj-chip bj-chip--green'
                  @disabled={{not this.gameCanStart}}
                  {{on 'click' (fn this.placeBet 50)}}
                >50</Button>
                <Button
                  @kind='text-only'
                  @size='auto'
                  class='bj-chip bj-chip--black'
                  @disabled={{not this.gameCanStart}}
                  {{on 'click' (fn this.placeBet 100)}}
                >100</Button>
                <Button
                  @kind='text-only'
                  @size='auto'
                  class='bj-chip bj-chip--purple'
                  @disabled={{not this.gameCanStart}}
                  {{on 'click' (fn this.placeBet 500)}}
                >500</Button>
              </div>
              <Button
                @kind='primary'
                @size='auto'
                class='bj-deal-btn'
                @disabled={{not this.gameCanStart}}
                {{on 'click' this.deal}}
              >Deal Cards</Button>
            {{/if}}

            {{#if (eq this.gameState 'playerTurn')}}
              <div class='bj-action-row'>
                <Button
                  @kind='text-only'
                  @size='auto'
                  class='bj-act-btn bj-act--hit'
                  {{on 'click' this.hit}}
                >
                  <span class='bj-act-icon'>👆</span>Hit
                </Button>
                <Button
                  @kind='text-only'
                  @size='auto'
                  class='bj-act-btn bj-act--stand'
                  {{on 'click' this.stand}}
                >
                  <span class='bj-act-icon'>✋</span>Stand
                </Button>
                <Button
                  @kind='text-only'
                  @size='auto'
                  class='bj-act-btn bj-act--double'
                  {{on 'click' this.doubleDown}}
                >
                  <span class='bj-act-icon'>⚡</span>Double
                </Button>
              </div>
            {{/if}}

            {{#if (eq this.gameState 'dealerTurn')}}
              <div class='bj-thinking'>
                <div class='bj-dot'></div>
                <div class='bj-dot'></div>
                <div class='bj-dot'></div>
                <span>Dealer thinking…</span>
              </div>
            {{/if}}

          </div>
        </div>
      </div>
    </div>

    <style scoped>
      /* ── Root table ────────────────────────────────────────── */
      .bj-table {
        /* ── Casino design tokens ──────────────────────────── */
        --casino-gold-dim: color-mix(
          in oklch,
          var(--accent-ink) 55%,
          transparent
        );
        --casino-gold-border: color-mix(
          in oklch,
          var(--accent) 22%,
          transparent
        );
        --casino-gold-glow: color-mix(in oklch, var(--accent) 45%, transparent);
        --casino-gold-shine: color-mix(
          in oklch,
          var(--accent) 90%,
          transparent
        );
        --casino-felt-bg: radial-gradient(
          ellipse at 50% 30%,
          var(--inset) 0%,
          var(--inset) 55%,
          var(--inset) 100%
        );
        --casino-felt-inner: color-mix(in oklch, var(--inset) 45%, transparent);
        --casino-panel: color-mix(in oklch, var(--inset) 42%, transparent);
        --casino-panel-mid: color-mix(in oklch, var(--inset) 38%, transparent);
        --casino-panel-dark: color-mix(in oklch, var(--inset) 48%, transparent);
        --casino-panel-light: color-mix(
          in oklch,
          var(--inset) 30%,
          transparent
        );
        --casino-panel-border: var(--border);
        --casino-ring-glow: color-mix(in oklch, var(--accent) 15%, transparent);
        --casino-font: 'Georgia', 'Times New Roman', serif;
        --casino-text: var(--card-foreground);
        --casino-text-muted: var(--muted-foreground);
        --casino-text-sub: var(--muted-foreground);
        --casino-text-light: var(--card-foreground);
        --casino-win-bg: color-mix(in oklch, var(--success) 40%, transparent);
        --casino-win-border: color-mix(
          in oklch,
          var(--success) 35%,
          transparent
        );
        --casino-lose-bg: color-mix(
          in oklch,
          var(--destructive) 40%,
          transparent
        );
        --casino-lose-border: color-mix(
          in oklch,
          var(--destructive) 35%,
          transparent
        );
        --casino-draw-bg: var(--muted);
        --casino-draw-border: color-mix(
          in oklch,
          var(--border) 25%,
          transparent
        );
        --casino-card-back-border: var(--border);
        --casino-score-perfect-bg: color-mix(
          in oklch,
          var(--accent) 25%,
          transparent
        );
        --casino-score-bust-bg: color-mix(
          in oklch,
          var(--destructive) 30%,
          transparent
        );
        --chip-red: linear-gradient(
          145deg,
          var(--destructive),
          var(--destructive)
        );
        --chip-blue: linear-gradient(145deg, var(--primary), var(--primary));
        --chip-green: linear-gradient(145deg, var(--success), var(--success));
        --chip-black: linear-gradient(145deg, var(--tooltip), var(--tooltip));
        --chip-purple: linear-gradient(145deg, var(--primary), var(--primary));
        --btn-hit: linear-gradient(145deg, var(--success), var(--success));
        --btn-stand: linear-gradient(
          145deg,
          var(--primary),
          var(--destructive)
        );
        --btn-double: linear-gradient(
          145deg,
          var(--destructive),
          var(--destructive)
        );

        background-color: var(--casino-felt-bg);
        height: 100%;
        width: 100%;
        color: var(--casino-text);
        font-family: var(--casino-font);
        display: flex;
        flex-direction: column;
        position: relative;
        overflow: hidden;
        /* Gold outer border */
        box-shadow:
          inset 0 0 0 3px var(--primary),
          inset 0 0 0 5px var(--casino-ring-glow);
      }

      /* Felt micro-texture */
      .bj-table::after {
        content: '';
        position: absolute;
        inset: 0;
        background-image:
          repeating-linear-gradient(
            0deg,
            transparent,
            transparent 0.1875rem,
            color-mix(in oklch, var(--foreground) 4%, transparent) 0.1875rem,
            color-mix(in oklch, var(--foreground) 4%, transparent) 0.25rem
          ),
          repeating-linear-gradient(
            90deg,
            transparent,
            transparent 0.1875rem,
            color-mix(in oklch, var(--foreground) 4%, transparent) 0.1875rem,
            color-mix(in oklch, var(--foreground) 4%, transparent) 0.25rem
          );
        pointer-events: none;
        z-index: 0;
      }

      /* ── Validation overlay ────────────────────────────────── */
      .bj-validation-overlay {
        position: absolute;
        inset: 0;
        z-index: 60;
        background-color: var(--overlay);
        color: var(--tooltip-foreground);
        backdrop-filter: blur(5px);
        -webkit-backdrop-filter: blur(5px);
        display: flex;
        justify-content: center;
        align-items: center;
      }
      .bj-validation-step-body {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-sm);
      }
      .bj-link-editor {
        width: 100%;
      }
      .bj-link-editor :deep(.links-to-editor) {
        display: grid;
        gap: var(--boxel-sp-sm);
      }
      .bj-link-editor :deep(.links-to-editor.can-write) {
        grid-template-columns: minmax(0, 1fr);
      }
      .bj-link-editor :deep(.add-new) {
        width: 100%;
        justify-content: center;
        min-height: 3rem;
        border-radius: 0.1875rem;
        border: 1px solid color-mix(in oklch, var(--accent) 50%, transparent);
        border-top: 2px solid
          color-mix(in oklch, var(--accent) 70%, transparent);
        background-color: var(--card);
        color: var(--accent-ink);
        box-shadow: none;
        text-transform: uppercase;
        letter-spacing: 0.12em;
        font-size: 0.8125rem;
        font-weight: 700;
        transition:
          background 0.15s ease,
          border-color 0.15s ease;
      }
      .bj-link-editor :deep(.add-new:hover),
      .bj-link-editor :deep(.add-new:focus-visible) {
        background-color: var(--card);
        border-color: color-mix(in oklch, var(--accent) 75%, transparent);
        color: var(--accent-ink);
      }
      .bj-link-editor :deep(.boxel-card-container.fitted-format) {
        border-radius: var(--boxel-border-radius);
        overflow: hidden;
        box-shadow:
          inset 0 0 0 1px color-mix(in oklch, var(--card) 4%, transparent),
          0 0 0 1px color-mix(in oklch, var(--accent) 18%, transparent),
          var(--boxel-box-shadow-sm);
      }
      .bj-link-editor :deep(.field-component-card.fitted-format) {
        min-height: 4.25rem;
      }
      .bj-link-editor :deep(.remove) {
        --icon-bg: color-mix(in oklch, var(--destructive) 95%, transparent);
        --icon-border: color-mix(in oklch, var(--destructive) 55%, transparent);
      }
      .bj-link-editor :deep(.remove:hover),
      .bj-link-editor :deep(.remove:focus-visible) {
        --icon-bg: color-mix(in oklch, var(--destructive) 100%, transparent);
        --icon-border: color-mix(in oklch, var(--destructive) 75%, transparent);
      }

      /* ── Outcome overlay ───────────────────────────────────── */
      .bj-outcome-overlay {
        position: absolute;
        inset: 0;
        z-index: 50;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: var(--boxel-sp-sm);
        animation: overlayIn 0.4s cubic-bezier(0.22, 1, 0.36, 1) both;
      }
      .bj-outcome--win {
        background: radial-gradient(
          ellipse at center,
          color-mix(in oklch, var(--accent) 40%, transparent) 0%,
          color-mix(in oklch, var(--foreground) 88%, transparent) 70%
        );
      }
      .bj-outcome--lose {
        background: radial-gradient(
          ellipse at center,
          color-mix(in oklch, var(--destructive) 40%, transparent) 0%,
          color-mix(in oklch, var(--foreground) 88%, transparent) 70%
        );
      }
      .bj-outcome--push {
        background: radial-gradient(
          ellipse at center,
          color-mix(in oklch, var(--muted) 40%, transparent) 0%,
          color-mix(in oklch, var(--foreground) 88%, transparent) 70%
        );
      }
      .bj-outcome-icon {
        font-size: 3.25rem;
        animation: iconPop 0.5s 0.15s cubic-bezier(0.22, 1, 0.36, 1) both;
      }
      .bj-outcome-title {
        font-size: 2rem;
        font-weight: bold;
        letter-spacing: 0.25rem;
        text-transform: uppercase;
        animation: titleSlideUp 0.4s 0.25s cubic-bezier(0.22, 1, 0.36, 1) both;
      }
      .bj-outcome--win .bj-outcome-title {
        color: var(--accent-ink);
        text-shadow: 0 0 30px var(--casino-gold-shine);
        animation:
          titleSlideUp 0.4s 0.25s cubic-bezier(0.22, 1, 0.36, 1) both,
          goldGlow 1.8s 0.7s ease-in-out infinite alternate;
      }
      .bj-outcome--lose .bj-outcome-title {
        color: var(--destructive-ink);
        text-shadow: 0 0 20px
          color-mix(in oklch, var(--destructive) 70%, transparent);
      }
      .bj-outcome--push .bj-outcome-title {
        color: var(--subtle-foreground);
      }
      .bj-outcome-sub {
        font-size: var(--boxel-font-size-sm);
        color: var(--casino-text-sub);
        letter-spacing: var(--boxel-lsp-xs);
        animation: titleSlideUp 0.4s 0.35s cubic-bezier(0.22, 1, 0.36, 1) both;
      }
      .bj-play-again-btn {
        margin-top: var(--boxel-sp);
        padding: var(--boxel-sp-sm) var(--boxel-sp-xl);
        background-color: var(--primary);
        color: var(--primary-foreground);
        border: none;
        border-radius: var(--boxel-border-radius-xl);
        font-size: var(--boxel-font-size);
        font-weight: bold;
        letter-spacing: var(--boxel-lsp-sm);
        cursor: pointer;
        box-shadow: 0 4px 22px var(--casino-gold-glow);
        animation:
          goldShimmer 2.5s linear infinite,
          titleSlideUp 0.4s 0.45s cubic-bezier(0.22, 1, 0.36, 1) both;
        transition:
          transform 0.2s,
          box-shadow 0.2s;
      }
      .bj-play-again-btn:hover {
        transform: scale(1.06);
        box-shadow: 0 6px 28px
          color-mix(in oklch, var(--accent) 60%, transparent);
      }

      /* ── Content wrapper ───────────────────────────────────── */
      .bj-content {
        position: relative;
        z-index: 1;
        display: flex;
        flex-direction: column;
        height: 100%;
        padding: var(--boxel-sp-sm);
        gap: var(--boxel-sp-xs);
        overflow: hidden;
      }

      /* ── Header ────────────────────────────────────────────── */
      .bj-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: var(--boxel-sp-xs) var(--boxel-sp);
        background-color: var(--casino-panel);
        border-radius: var(--boxel-border-radius);
        border: 1px solid var(--casino-gold-border);
        flex-shrink: 0;
      }
      .bj-casino-title {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        font-size: var(--boxel-font-size);
        font-weight: bold;
        letter-spacing: var(--boxel-lsp-xs);
      }
      .bj-title-text {
        color: var(--accent-ink);
      }
      .bj-suit-accent {
        color: var(--accent-ink);
        font-size: var(--boxel-font-size-sm);
      }

      .bj-stats {
        display: flex;
        gap: var(--boxel-sp-xs);
      }
      .bj-stat {
        display: flex;
        flex-direction: column;
        align-items: center;
        padding: 0.1875rem var(--boxel-sp-sm);
        border-radius: var(--boxel-border-radius-sm);
        background-color: var(--casino-panel-mid);
        border: 1px solid var(--border);
        min-width: 2.875rem;
      }
      .bj-stat-label {
        font-size: 0.5625rem;
        color: var(--casino-text-muted);
        text-transform: uppercase;
        letter-spacing: var(--boxel-lsp-xs);
      }
      .bj-stat-val {
        font-size: var(--boxel-font-size-sm);
        font-weight: bold;
        line-height: 1.2;
      }
      .bj-stat-val--wins {
        color: var(--success-ink);
      }
      .bj-stat-val--losses {
        color: var(--destructive-ink);
      }
      .bj-stat-val--pos {
        color: var(--success-ink);
      }
      .bj-stat-val--neg {
        color: var(--destructive-ink);
      }

      /* ── Felt area ─────────────────────────────────────────── */
      .bj-felt {
        flex: 1;
        display: flex;
        flex-direction: column;
        justify-content: space-between;
        padding: var(--boxel-sp-sm) var(--boxel-sp);
        background-color: var(--casino-felt-inner);
        border-radius: var(--boxel-border-radius-lg);
        border: 1px solid color-mix(in oklch, var(--accent) 12%, transparent);
        box-shadow: inset 0 0 40px
          color-mix(in oklch, var(--shadow-color) 45%, transparent);
        min-height: 0;
        overflow: hidden;
        gap: var(--boxel-sp-xs);
      }

      /* ── Player zones ──────────────────────────────────────── */
      .bj-zone {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
      }
      .bj-zone-bar {
        display: flex;
        justify-content: space-between;
        align-items: center;
      }

      .bj-player-pill {
        font-size: var(--boxel-font-size-xs);
      }

      /* Score badge */
      .bj-score-badge {
        padding: 2px var(--boxel-sp);
        border-radius: var(--boxel-border-radius-xl);
        font-size: var(--boxel-font-size);
        font-weight: bold;
        min-width: 2.75rem;
        text-align: center;
        background-color: var(--casino-panel-dark);
        border: 1px solid var(--border);
        transition: all 0.3s;
      }
      .bj-score-badge--hidden {
        color: var(--casino-text-muted);
        letter-spacing: 0.25rem;
      }
      .bj-score--perfect {
        background-color: var(--casino-score-perfect-bg);
        border-color: var(--accent);
        color: var(--accent-ink);
        box-shadow: 0 0 14px var(--casino-gold-glow);
        animation: badgePulse 1.2s ease-in-out infinite alternate;
      }
      .bj-score--bust {
        background-color: var(--casino-score-bust-bg);
        border-color: var(--destructive);
        color: var(--destructive-ink);
        box-shadow: 0 0 12px
          color-mix(in oklch, var(--destructive) 40%, transparent);
      }

      /* ── Cards ─────────────────────────────────────────────── */
      .bj-cards {
        display: flex;
        gap: var(--boxel-sp-sm);
        min-height: 6rem;
        flex-wrap: wrap;
        align-items: flex-start;
      }

      .bj-card {
        position: relative;
        width: 4.25rem;
        height: 6.25rem;
        border-radius: var(--boxel-border-radius);
        background-color: var(--card);
        color: var(--card-foreground);
        box-shadow:
          2px 5px 14px color-mix(in oklch, var(--shadow-color) 55%, transparent),
          0 0 0 1px color-mix(in oklch, var(--shadow-color) 8%, transparent);
        display: flex;
        flex-direction: column;
        justify-content: space-between;
        padding: 0.3125rem 0.375rem;
        flex-shrink: 0;
        animation: cardDeal 0.3s cubic-bezier(0.22, 1, 0.36, 1) both;
        transition:
          transform 0.18s,
          box-shadow 0.18s;
      }
      .bj-card:hover {
        transform: translateY(-7px) rotate(1.5deg);
        box-shadow: 4px 12px 22px
          color-mix(in oklch, var(--shadow-color) 65%, transparent);
      }

      /* Inner inset border on face-up cards */
      .bj-card:not(.bj-card--back)::before {
        content: '';
        position: absolute;
        inset: 0.1875rem;
        border: 1px solid var(--border);
        border-radius: 0.3125rem;
        pointer-events: none;
      }

      /* Card back — classic crosshatch */
      .bj-card--back {
        background-color: var(--card);
        color: var(--card-foreground);
        background-image:
          repeating-linear-gradient(
            45deg,
            color-mix(in oklch, var(--card) 6%, transparent) 0,
            color-mix(in oklch, var(--card) 6%, transparent) 2px,
            transparent 0,
            transparent 50%
          ),
          repeating-linear-gradient(
            -45deg,
            color-mix(in oklch, var(--card) 6%, transparent) 0,
            color-mix(in oklch, var(--card) 6%, transparent) 2px,
            transparent 0,
            transparent 50%
          );
        background-size: 0.625rem 0.625rem;
        border: 2px solid var(--casino-card-back-border);
      }
      .bj-card--back::after {
        content: '♦';
        position: absolute;
        inset: 0;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 2.625rem;
        color: color-mix(in oklch, var(--card-foreground) 8%, transparent);
      }

      /* Card corners */
      .bj-card-corner {
        display: flex;
        flex-direction: column;
        align-items: flex-start;
        line-height: 1.1;
      }
      .bj-card-br {
        transform: rotate(180deg);
      }
      .bj-cv {
        font-size: 0.9375rem;
        font-weight: bold;
        color: var(--foreground);
        line-height: 1;
      }
      .bj-cp {
        font-size: 0.75rem;
        line-height: 1;
      }

      /* Center pip */
      .bj-card-center {
        position: absolute;
        top: 50%;
        left: 50%;
        transform: translate(-50%, -50%);
        font-size: 1.875rem;
        line-height: 1;
        opacity: 0.88;
        pointer-events: none;
      }

      /* Suit colours */
      .bj-suit-hearts,
      .bj-suit-diamonds {
        color: var(--destructive-ink);
      }
      .bj-suit-clubs,
      .bj-suit-spades {
        color: var(--foreground);
      }

      /* nth-child deal-delay stagger */
      .bj-card:nth-child(1) {
        animation-delay: 0s;
      }
      .bj-card:nth-child(2) {
        animation-delay: 0.1s;
      }
      .bj-card:nth-child(3) {
        animation-delay: 0.2s;
      }
      .bj-card:nth-child(4) {
        animation-delay: 0.3s;
      }
      .bj-card:nth-child(5) {
        animation-delay: 0.4s;
      }

      /* ── Divider ────────────────────────────────────────────── */
      .bj-divider {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-sm);
        padding: 2px 0;
      }
      .bj-divider-line {
        flex: 1;
        height: 1px;
        background: linear-gradient(
          90deg,
          transparent,
          var(--casino-gold-dim),
          transparent
        );
      }
      .bj-divider-text {
        font-size: 0.5625rem;
        color: color-mix(in oklch, var(--accent-ink) 85%, transparent);
        letter-spacing: var(--boxel-lsp-xl);
        text-transform: uppercase;
        white-space: nowrap;
      }

      /* ── Bottom controls ───────────────────────────────────── */
      .bj-bottom {
        flex-shrink: 0;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
      }

      /* Status bar */
      .bj-status {
        text-align: center;
        padding: var(--boxel-sp-xs) var(--boxel-sp);
        border-radius: var(--boxel-border-radius);
        font-size: var(--boxel-font-size-sm);
        letter-spacing: var(--boxel-lsp-xs);
        background-color: var(--casino-panel-dark);
        border: 1px solid var(--casino-panel-border);
        transition:
          background 0.35s,
          border-color 0.35s,
          color 0.35s;
      }
      .bj-status--win {
        background-color: var(--casino-win-bg);
        border-color: var(--casino-win-border);
        color: var(--success-ink);
      }
      .bj-status--lose {
        background-color: var(--casino-lose-bg);
        border-color: var(--casino-lose-border);
        color: var(--destructive-ink);
      }
      .bj-status--push {
        background-color: var(--casino-draw-bg);
        border-color: var(--casino-draw-border);
        color: var(--subtle-foreground);
      }

      /* Bankroll */
      .bj-bankroll {
        display: flex;
        justify-content: space-between;
        align-items: center;
      }
      .bj-chips-pill {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        background-color: var(--casino-panel-mid);
        padding: 0.25rem var(--boxel-sp-sm);
        border-radius: var(--boxel-border-radius-xl);
        border: 1px solid var(--casino-gold-border);
      }
      .bj-chips-icon {
        font-size: var(--boxel-font-size-sm);
      }
      .bj-chips-num {
        font-size: var(--boxel-font-size);
        font-weight: bold;
        color: var(--accent-ink);
      }
      .bj-chips-lbl {
        font-size: var(--boxel-font-size-xs);
        color: var(--casino-text-muted);
      }

      .bj-bet-pill {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        background-color: color-mix(in oklch, var(--accent) 12%, transparent);
        border: 1px solid color-mix(in oklch, var(--accent) 38%, transparent);
        padding: 0.25rem var(--boxel-sp);
        border-radius: var(--boxel-border-radius-xl);
      }
      .bj-bet-lbl {
        font-size: 0.5625rem;
        color: color-mix(in oklch, var(--accent-ink) 65%, transparent);
        letter-spacing: var(--boxel-lsp-sm);
        text-transform: uppercase;
      }
      .bj-bet-num {
        font-size: var(--boxel-font-size);
        font-weight: bold;
        color: var(--accent-ink);
      }

      /* Controls shell */
      .bj-controls {
        background-color: var(--casino-panel-light);
        border-radius: var(--boxel-border-radius);
        padding: var(--boxel-sp-sm);
        border: 1px solid var(--border);
      }

      /* ── Betting chips ─────────────────────────────────────── */
      .bj-chip-row {
        display: flex;
        justify-content: center;
        gap: var(--boxel-sp-sm);
        flex-wrap: wrap;
        margin-bottom: var(--boxel-sp-sm);
      }
      .bj-chip {
        width: 3.125rem;
        height: 3.125rem;
        border-radius: 50%;
        font-weight: bold;
        font-size: var(--boxel-font-size-xs);
        cursor: pointer;
        border: none;
        color: var(--casino-text);
        display: flex;
        align-items: center;
        justify-content: center;
        box-shadow:
          0 5px 10px color-mix(in oklch, var(--shadow-color) 50%, transparent),
          inset 0 1px 0 color-mix(in oklch, var(--card) 25%, transparent),
          0 0 0 4px color-mix(in oklch, var(--card) 12%, transparent);
        transition:
          transform 0.15s,
          box-shadow 0.15s;
        position: relative;
        overflow: hidden;
      }
      /* Chip dashed ring */
      .bj-chip::before {
        content: '';
        position: absolute;
        inset: 0.3125rem;
        border-radius: 50%;
        border: 2px dashed var(--border);
        pointer-events: none;
      }
      .bj-chip:hover:not(:disabled) {
        transform: translateY(-4px) scale(1.1);
        box-shadow:
          0 9px 18px color-mix(in oklch, var(--shadow-color) 55%, transparent),
          inset 0 1px 0 color-mix(in oklch, var(--card) 30%, transparent),
          0 0 0 4px color-mix(in oklch, var(--card) 18%, transparent);
      }
      .bj-chip:active:not(:disabled) {
        transform: scale(0.95);
      }
      .bj-chip:disabled {
        opacity: 0.38;
        cursor: not-allowed;
      }

      .bj-chip--red {
        background: var(--chip-red);
      }
      .bj-chip--blue {
        background: var(--chip-blue);
      }
      .bj-chip--green {
        background: var(--chip-green);
      }
      .bj-chip--black {
        background: var(--chip-black);
      }
      .bj-chip--purple {
        background: var(--chip-purple);
      }

      /* ── Deal button ───────────────────────────────────────── */
      .bj-deal-btn {
        display: block;
        width: 100%;
        padding: var(--boxel-sp-sm);
        border: none;
        border-radius: var(--boxel-border-radius);
        font-size: var(--boxel-font-size);
        font-weight: bold;
        letter-spacing: var(--boxel-lsp-sm);
        cursor: pointer;
        background-color: var(--primary);
        color: var(--primary-foreground);
        box-shadow:
          0 4px 18px var(--casino-gold-glow),
          inset 0 1px 0 color-mix(in oklch, var(--card) 25%, transparent);
        animation: goldShimmer 3s linear infinite;
        transition:
          transform 0.18s,
          box-shadow 0.18s;
      }
      .bj-deal-btn:hover:not(:disabled) {
        transform: translateY(-2px);
        box-shadow: 0 8px 26px
          color-mix(in oklch, var(--accent) 50%, transparent);
      }
      .bj-deal-btn:active:not(:disabled) {
        transform: translateY(1px);
      }
      .bj-deal-btn:disabled {
        opacity: 0.38;
        cursor: not-allowed;
        animation: none;
      }

      /* ── Action buttons (Hit / Stand / Double) ─────────────── */
      .bj-action-row {
        display: flex;
        gap: var(--boxel-sp-sm);
      }
      .bj-act-btn {
        flex: 1;
        padding: var(--boxel-sp-sm) var(--boxel-sp-xs);
        border: none;
        border-radius: var(--boxel-border-radius);
        font-size: var(--boxel-font-size-sm);
        font-weight: bold;
        letter-spacing: var(--boxel-lsp-xs);
        cursor: pointer;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 0.1875rem;
        box-shadow:
          0 4px 12px color-mix(in oklch, var(--shadow-color) 40%, transparent),
          inset 0 1px 0 color-mix(in oklch, var(--card) 15%, transparent);
        transition:
          transform 0.15s,
          box-shadow 0.15s;
      }
      .bj-act-icon {
        font-size: var(--boxel-font-size-lg);
      }
      .bj-act-btn:hover {
        transform: translateY(-3px);
        box-shadow: 0 7px 18px
          color-mix(in oklch, var(--shadow-color) 50%, transparent);
      }
      .bj-act-btn:active {
        transform: translateY(1px);
      }
      .bj-act--hit {
        background: var(--btn-hit);
        color: var(--casino-text);
      }
      .bj-act--stand {
        background: var(--btn-stand);
        color: var(--casino-text);
      }
      .bj-act--double {
        background: var(--btn-double);
        color: var(--casino-text);
      }

      /* ── Dealer thinking ───────────────────────────────────── */
      .bj-thinking {
        display: flex;
        align-items: center;
        justify-content: center;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp);
        color: var(--casino-text-sub);
        font-style: italic;
        letter-spacing: var(--boxel-lsp-xs);
      }
      .bj-dot {
        width: 0.5rem;
        height: 0.5rem;
        border-radius: 50%;
        background-color: var(--accent);
        color: var(--accent-foreground);
        animation: dotBounce 1.3s ease-in-out infinite;
      }
      .bj-dot:nth-child(2) {
        animation-delay: 0.2s;
      }
      .bj-dot:nth-child(3) {
        animation-delay: 0.4s;
      }

      /* ── Keyframes ─────────────────────────────────────────── */
      @keyframes cardDeal {
        from {
          opacity: 0;
          transform: translateY(-18px) scale(0.82) rotate(-4deg);
        }
        to {
          opacity: 1;
          transform: translateY(0) scale(1) rotate(0deg);
        }
      }

      @keyframes overlayIn {
        from {
          opacity: 0;
          transform: scale(0.96);
        }
        to {
          opacity: 1;
          transform: scale(1);
        }
      }

      @keyframes iconPop {
        from {
          opacity: 0;
          transform: scale(0.2) rotate(-15deg);
        }
        to {
          opacity: 1;
          transform: scale(1) rotate(0deg);
        }
      }

      @keyframes titleSlideUp {
        from {
          opacity: 0;
          transform: translateY(14px);
        }
        to {
          opacity: 1;
          transform: translateY(0);
        }
      }

      @keyframes goldGlow {
        from {
          text-shadow: 0 0 16px
            color-mix(in oklch, var(--accent) 50%, transparent);
        }
        to {
          text-shadow:
            0 0 40px color-mix(in oklch, var(--accent) 100%, transparent),
            0 0 80px color-mix(in oklch, var(--accent) 35%, transparent);
        }
      }

      @keyframes goldShimmer {
        0% {
          background-position: 0% 50%;
        }
        50% {
          background-position: 100% 50%;
        }
        100% {
          background-position: 0% 50%;
        }
      }

      @keyframes badgePulse {
        from {
          box-shadow: 0 0 6px
            color-mix(in oklch, var(--accent) 30%, transparent);
        }
        to {
          box-shadow: 0 0 22px
            color-mix(in oklch, var(--accent) 85%, transparent);
        }
      }

      @keyframes dotBounce {
        0%,
        60%,
        100% {
          transform: translateY(0);
        }
        30% {
          transform: translateY(-9px);
        }
      }

      /* ── Responsive ────────────────────────────────────────── */
      @media (max-height: 720px) {
        .bj-card {
          width: 3.625rem;
          height: 5.375rem;
        }
        .bj-cv {
          font-size: 0.8125rem;
        }
        .bj-cp {
          font-size: 0.625rem;
        }
        .bj-card-center {
          font-size: 1.5rem;
        }
        .bj-casino-title {
          font-size: var(--boxel-font-size-sm);
        }
        .bj-chip {
          width: 2.625rem;
          height: 2.625rem;
          font-size: 0.6875rem;
        }
        .bj-act-btn {
          padding: var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-xs);
        }
        .bj-act-icon {
          font-size: var(--boxel-font-size);
        }
      }

      @media (max-width: 560px) {
        .bj-header {
          flex-direction: column;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .bj-stats {
          justify-content: center;
        }
        .bj-card {
          width: 3.625rem;
          height: 5.375rem;
        }
        .bj-card-center {
          font-size: 1.5rem;
        }
        .bj-chip {
          width: 2.625rem;
          height: 2.625rem;
          font-size: 0.6875rem;
        }
        .bj-action-row {
          flex-wrap: wrap;
        }
        .bj-outcome-title {
          font-size: 1.5rem;
          letter-spacing: 2px;
        }
      }
    </style>
  </template>
}

class FittedTemplate extends Component<typeof Blackjack> {
  get casinoName() {
    return this.args.model.casinoName?.trim() || 'Royal Casino';
  }

  <template>
    <article class='bj-fitted'>

      {{! ── BADGE ≤150×169 ── }}
      <div class='layout-badge'>
        <div class='logo-chip' aria-hidden='true'>
          <span class='logo-chip__number'>21</span>
        </div>
        <span class='bj-label'>BLACKJACK</span>
      </div>

      {{! ── STRIP 151+×≤169 ── }}
      <div class='layout-strip'>
        <div class='logo-chip logo-chip--sm' aria-hidden='true'>
          <span class='logo-chip__number'>21</span>
        </div>
        <div class='strip-copy'>
          <span class='bj-title'>BLACKJACK</span>
          <span class='bj-sub'>{{this.casinoName}}</span>
        </div>
        <div class='chip-row chip-row--1' aria-hidden='true'>
          <span class='casino-chip casino-chip--black'>100</span>
        </div>
      </div>

      {{! ── TILE ≤399×170+ ── }}
      <div class='layout-tile'>
        <div class='tile-top' aria-hidden='true'>
          <span class='pays-text'>BLACKJACK PAYS 3 TO 2</span>
        </div>
        <div class='tile-center'>
          <div class='logo-lockup'>
            <div class='logo-chip logo-chip--md' aria-hidden='true'>
              <span class='logo-chip__number'>21</span>
            </div>
            <div class='logo-suits' aria-hidden='true'>
              <span class='suit suit--spade'>♠</span>
              <span class='suit suit--heart'>♥</span>
              <span class='suit suit--diamond'>♦</span>
              <span class='suit suit--club'>♣</span>
            </div>
          </div>
          <h3 class='bj-title bj-title--tile'>BLACKJACK</h3>
          <p class='bj-sub'>{{this.casinoName}}</p>
        </div>
        <div class='chip-row chip-row--3' aria-hidden='true'>
          <span class='casino-chip casino-chip--red'>5</span>
          <span class='casino-chip casino-chip--green'>50</span>
          <span class='casino-chip casino-chip--black'>100</span>
        </div>
      </div>

      {{! ── CARD 400+×170+ ── }}
      <div class='layout-card'>
        {{! Left showpiece }}
        <div class='card-showpiece' aria-hidden='true'>
          <div class='showpiece-bg'></div>
          <div class='playing-cards'>
            <span class='play-card play-card--back play-card--left'></span>
            <span class='play-card play-card--red'>A♥</span>
            <span class='play-card play-card--black'>K♠</span>
          </div>
          <div class='logo-chip logo-chip--lg'>
            <span class='logo-chip__number'>21</span>
          </div>
          <span class='pays-text pays-text--arc'>BLACKJACK PAYS 3 TO 2</span>
        </div>

        {{! Right info panel }}
        <div class='card-info'>
          <div class='card-info__top'>
            <span class='bj-eyebrow'>{{this.casinoName}}</span>
            <h3 class='bj-title bj-title--hero'>BLACKJACK</h3>
            <p class='bj-tagline'>
              Hit, stand, double down — chase twenty-one.
            </p>
          </div>
          <div class='card-info__bottom'>
            <div class='chip-row chip-row--5' aria-hidden='true'>
              <span class='casino-chip casino-chip--red'>5</span>
              <span class='casino-chip casino-chip--blue'>20</span>
              <span class='casino-chip casino-chip--green'>50</span>
              <span class='casino-chip casino-chip--black'>100</span>
              <span class='casino-chip casino-chip--purple'>500</span>
            </div>
          </div>
        </div>
      </div>

    </article>

    <style scoped>
      /* ── Design tokens ─────────────────────────────────── */
      .bj-fitted {
        --gold: var(--accent);
        --gold-dim: color-mix(in oklch, var(--accent-ink) 70%, transparent);
        --gold-border: color-mix(in oklch, var(--accent) 30%, transparent);
        --gold-glow: color-mix(in oklch, var(--accent) 55%, transparent);
        --cream-dim: var(--overlay);
        --felt-bg: radial-gradient(
          ellipse at 50% 25%,
          var(--inset) 0%,
          var(--inset) 55%,
          var(--inset) 100%
        );
        --felt-sheen: radial-gradient(
          circle at 18% 12%,
          color-mix(in oklch, var(--card) 60%, transparent),
          transparent 30%
        );
        --panel-border: color-mix(in oklch, var(--inset) 45%, transparent);
        --chip-red: linear-gradient(
          145deg,
          var(--destructive),
          var(--destructive)
        );
        --chip-blue: linear-gradient(145deg, var(--primary), var(--primary));
        --chip-green: linear-gradient(145deg, var(--success), var(--success));
        --chip-black: linear-gradient(145deg, var(--tooltip), var(--tooltip));
        --chip-purple: linear-gradient(145deg, var(--primary), var(--primary));
        --casino-font: 'Georgia', 'Times New Roman', serif;

        width: 100%;
        height: 100%;
        color: var(--foreground);
        font-family: var(--casino-font);
        container-type: size;
      }

      /* ── Shared layout shell ───────────────────────────── */
      .layout-badge,
      .layout-strip,
      .layout-tile,
      .layout-card {
        display: none;
        width: 100%;
        height: 100%;
        box-sizing: border-box;
        overflow: hidden;
        border-radius: 0.875rem;
        border: 1px solid var(--gold-border);
        background: var(--felt-sheen), var(--felt-bg);
        box-shadow:
          inset 0 0 0 2px var(--panel-border),
          inset 0 -3rem 6rem
            color-mix(in oklch, var(--shadow-color) 30%, transparent),
          0 0.5rem 1.5rem
            color-mix(in oklch, var(--shadow-color) 25%, transparent);
        position: relative;
      }

      /* Felt micro-texture overlay */
      .layout-badge::after,
      .layout-strip::after,
      .layout-tile::after,
      .layout-card::after {
        content: '';
        position: absolute;
        inset: 0;
        border-radius: inherit;
        background-image:
          repeating-linear-gradient(
            0deg,
            transparent,
            transparent 0.1875rem,
            color-mix(in oklch, var(--foreground) 2%, transparent) 0.1875rem,
            color-mix(in oklch, var(--foreground) 2%, transparent) 0.25rem
          ),
          repeating-linear-gradient(
            90deg,
            transparent,
            transparent 0.1875rem,
            color-mix(in oklch, var(--foreground) 2%, transparent) 0.1875rem,
            color-mix(in oklch, var(--foreground) 2%, transparent) 0.25rem
          );
        pointer-events: none;
        z-index: 0;
      }

      /* ── Logo chip ─────────────────────────────────────── */
      .logo-chip {
        position: relative;
        display: flex;
        align-items: center;
        justify-content: center;
        border-radius: 50%;
        flex-shrink: 0;
        /* Conic casino chip pattern */
        background:
          radial-gradient(circle, var(--success) 0 36%, transparent 37%),
          repeating-conic-gradient(
            from 0deg,
            var(--primary) 0deg 9deg,
            var(--destructive) 9deg 20deg
          );
        box-shadow:
          0 0 0 2px color-mix(in oklch, var(--primary) 18%, transparent),
          0 0.3rem 1rem
            color-mix(in oklch, var(--shadow-color) 50%, transparent),
          0 0 1.5rem var(--gold-glow);
        z-index: 1;
      }

      .logo-chip__number {
        font-size: inherit;
        font-weight: 900;
        color: var(--gold);
        letter-spacing: -0.02em;
        text-shadow:
          0 0 8px var(--gold-glow),
          0 1px 2px color-mix(in oklch, var(--shadow-color) 60%, transparent);
        z-index: 2;
        line-height: 1;
      }

      .logo-chip--sm {
        width: 2.1rem;
        height: 2.1rem;
        font-size: 0.78rem;
      }

      .logo-chip--md {
        width: 3.5rem;
        height: 3.5rem;
        font-size: 1.15rem;
        animation: chipGlow 2.5s ease-in-out infinite alternate;
      }

      .logo-chip--lg {
        width: clamp(3.8rem, 16cqw, 6.5rem);
        height: clamp(3.8rem, 16cqw, 6.5rem);
        font-size: clamp(1.2rem, 4.5cqw, 2rem);
        animation: chipGlow 2.5s ease-in-out infinite alternate;
      }

      /* ── Typography ────────────────────────────────────── */
      .bj-label {
        font-size: 0.52rem;
        font-weight: 700;
        letter-spacing: 0.16em;
        text-transform: uppercase;
        color: var(--cream-dim);
      }

      .bj-eyebrow {
        font-size: 0.62rem;
        font-weight: 600;
        letter-spacing: 0.18em;
        text-transform: uppercase;
        color: var(--cream-dim);
        margin: 0;
      }

      .bj-title {
        margin: 0;
        font-size: 1rem;
        font-weight: 800;
        letter-spacing: 0.2em;
        text-transform: uppercase;
        color: var(--gold);
        line-height: 1;
        text-shadow: 0 0 18px var(--gold-glow);
        white-space: nowrap;
      }

      .bj-title--tile {
        font-size: clamp(1.1rem, 7cqw, 1.7rem);
        margin-top: 0.4rem;
        animation: goldPulse 3s ease-in-out infinite alternate;
      }

      .bj-title--hero {
        font-size: clamp(1.6rem, 6cqw, 3rem);
        letter-spacing: 0.18em;
        animation: goldPulse 3s ease-in-out infinite alternate;
      }

      .bj-sub {
        margin: 0.2rem 0 0;
        font-size: 0.68rem;
        color: var(--cream-dim);
        letter-spacing: 0.04em;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .bj-tagline {
        margin: 0.35rem 0 0;
        font-size: 0.72rem;
        color: var(--cream-dim);
        font-style: italic;
        line-height: 1.4;
      }

      /* ── Suit symbols ──────────────────────────────────── */
      .logo-suits {
        display: flex;
        gap: 0.22rem;
        margin-top: 0.4rem;
      }

      .suit {
        font-size: 0.85rem;
        line-height: 1;
        opacity: 0.75;
      }

      .suit--heart,
      .suit--diamond {
        color: var(--destructive-ink);
      }

      .suit--spade,
      .suit--club {
        color: var(--foreground);
      }

      /* ── Casino chips ──────────────────────────────────── */
      .chip-row {
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 0.45rem;
        z-index: 1;
        position: relative;
      }

      .casino-chip {
        display: flex;
        align-items: center;
        justify-content: center;
        border-radius: 50%;
        font-size: 0.56rem;
        font-weight: 700;
        color: var(--foreground);
        line-height: 1;
        position: relative;
        overflow: hidden;
        /* Chip ring */
        box-shadow:
          0 0 0 2px color-mix(in oklch, var(--card) 18%, transparent),
          0 3px 8px color-mix(in oklch, var(--shadow-color) 55%, transparent),
          inset 0 1px 0 color-mix(in oklch, var(--card) 22%, transparent);
      }

      /* Dashed inner ring */
      .casino-chip::before {
        content: '';
        position: absolute;
        inset: 0.1875rem;
        border-radius: 50%;
        border: 1.5px dashed var(--border);
        pointer-events: none;
      }

      .casino-chip--red {
        background: var(--chip-red);
      }
      .casino-chip--blue {
        background: var(--chip-blue);
      }
      .casino-chip--green {
        background: var(--chip-green);
      }
      .casino-chip--black {
        background: var(--chip-black);
      }
      .casino-chip--purple {
        background: var(--chip-purple);
      }

      /* ── Pays text ─────────────────────────────────────── */
      .pays-text {
        font-size: 0.58rem;
        font-weight: 700;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color: var(--gold-dim);
        white-space: nowrap;
      }

      /* ── BADGE layout ──────────────────────────────────── */
      .layout-badge {
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 0.3rem;
        padding: 0.4rem 0.3rem;
      }

      /* ── STRIP layout ──────────────────────────────────── */
      .layout-strip {
        flex-direction: row;
        align-items: center;
        gap: 0.6rem;
        padding: 0.5rem 0.7rem;
      }

      .strip-copy {
        flex: 1;
        display: flex;
        flex-direction: column;
        min-width: 0;
        gap: 0.15rem;
      }

      /* Strip chip sizing */
      .chip-row--1 .casino-chip {
        width: 2rem;
        height: 2rem;
        font-size: 0.6rem;
      }

      /* ── TILE layout ───────────────────────────────────── */
      .layout-tile {
        flex-direction: column;
        align-items: center;
        justify-content: space-between;
        padding: 0.6rem 0.75rem;
        gap: 0.4rem;
        text-align: center;
      }

      .tile-top {
        z-index: 1;
      }

      .tile-center {
        flex: 1;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 0;
        z-index: 1;
      }

      .logo-lockup {
        display: flex;
        flex-direction: column;
        align-items: center;
      }

      /* Tile chip sizing */
      .chip-row--3 .casino-chip {
        width: clamp(1.8rem, 8cqw, 2.5rem);
        height: clamp(1.8rem, 8cqw, 2.5rem);
        font-size: clamp(0.55rem, 2cqw, 0.72rem);
      }

      /* ── CARD layout ───────────────────────────────────── */
      .layout-card {
        flex-direction: row;
        align-items: stretch;
      }

      /* Left showpiece */
      .card-showpiece {
        position: relative;
        width: 42%;
        flex-shrink: 0;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 0.6rem;
        padding: 0.75rem 0.5rem;
        z-index: 1;
        /* Subtle inner separator */
        border-right: 1px solid var(--gold-border);
        background-color: var(--hover);
      }

      .showpiece-bg {
        position: absolute;
        inset: 0;
        background: radial-gradient(
          ellipse at center,
          color-mix(in oklch, var(--accent) 7%, transparent),
          transparent 70%
        );
        pointer-events: none;
      }

      .pays-text--arc {
        margin-top: 0.4rem;
        text-align: center;
      }

      /* Playing cards fan */
      .playing-cards {
        position: relative;
        width: clamp(5rem, 18cqw, 8rem);
        height: clamp(3.5rem, 14cqw, 6rem);
        flex-shrink: 0;
      }

      .play-card {
        position: absolute;
        display: flex;
        align-items: center;
        justify-content: center;
        width: 48%;
        height: 90%;
        border-radius: 0.3rem;
        font-size: clamp(0.65rem, 2.5cqw, 1rem);
        font-weight: 800;
        box-shadow:
          0 4px 14px color-mix(in oklch, var(--shadow-color) 50%, transparent),
          0 0 0 1px color-mix(in oklch, var(--shadow-color) 10%, transparent);
      }

      .play-card--back {
        background:
          repeating-linear-gradient(
            45deg,
            color-mix(in oklch, var(--card) 6%, transparent) 0,
            color-mix(in oklch, var(--card) 6%, transparent) 2px,
            transparent 0,
            transparent 50%
          ),
          var(--card);
        background-size:
          0.5rem 0.5rem,
          auto;
        left: 0;
        top: 8%;
        rotate: -10deg;
        z-index: 0;
      }

      .play-card--red {
        background-color: var(--card);
        color: var(--card-foreground);
        left: 24%;
        top: 0;
        rotate: -3deg;
        z-index: 1;
      }

      .play-card--black {
        background-color: var(--card);
        color: var(--foreground);
        right: 0;
        top: 4%;
        rotate: 9deg;
        z-index: 2;
      }

      /* Right info panel */
      .card-info {
        flex: 1;
        display: flex;
        flex-direction: column;
        justify-content: space-between;
        padding: 0.85rem 0.9rem;
        z-index: 1;
        min-width: 0;
      }

      .card-info__top {
        display: flex;
        flex-direction: column;
        gap: 0.25rem;
      }

      .card-info__bottom {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
      }

      /* Card chip sizing */
      .chip-row--5 .casino-chip {
        width: clamp(1.6rem, 5cqw, 2.6rem);
        height: clamp(1.6rem, 5cqw, 2.6rem);
        font-size: clamp(0.48rem, 1.5cqw, 0.72rem);
      }

      /* ── Player rows ───────────────────────────────────── */
      /* ── Animations ────────────────────────────────────── */
      @keyframes chipGlow {
        from {
          box-shadow:
            0 0 0 2px color-mix(in oklch, var(--primary) 18%, transparent),
            0 0.3rem 1rem
              color-mix(in oklch, var(--shadow-color) 50%, transparent),
            0 0 0.8rem var(--gold-glow);
        }
        to {
          box-shadow:
            0 0 0 2px color-mix(in oklch, var(--primary) 30%, transparent),
            0 0.3rem 1rem
              color-mix(in oklch, var(--shadow-color) 50%, transparent),
            0 0 2.5rem var(--gold-glow);
        }
      }

      @keyframes goldPulse {
        from {
          text-shadow: 0 0 10px
            color-mix(in oklch, var(--accent) 40%, transparent);
        }
        to {
          text-shadow:
            0 0 28px color-mix(in oklch, var(--accent) 90%, transparent),
            0 0 48px color-mix(in oklch, var(--accent) 25%, transparent);
        }
      }

      /* ── Container breakpoints ─────────────────────────── */

      /* Badge: ≤150px wide OR ≤169px tall in tiny box */
      @container (max-width: 150px) and (max-height: 169px) {
        .layout-badge {
          display: flex;
        }
        .logo-chip--sm {
          width: 2.6rem;
          height: 2.6rem;
          font-size: 0.95rem;
        }
      }

      /* Strip: wider but still short */
      @container (min-width: 151px) and (max-height: 169px) {
        .layout-strip {
          display: flex;
        }
      }

      /* Tile: taller, narrower */
      @container (max-width: 399px) and (min-height: 170px) {
        .layout-tile {
          display: flex;
        }
      }

      /* Card: wide & tall */
      @container (min-width: 400px) and (min-height: 170px) {
        .layout-card {
          display: flex;
        }
      }
    </style>
  </template>
}

export class Blackjack extends CardDef {
  static displayName = 'Blackjack';
  static prefersWideFormat = true;

  @field casinoName = contains(StringField);

  @field player = linksTo(() => Player, { searchable: true });
  @field dealer = linksTo(() => Player, { searchable: true });

  @field playerChips = contains(NumberField);
  @field currentBet = contains(NumberField);
  @field gameState = contains(StringField);
  @field gameMessage = contains(StringField);
  @field statistics = contains(StatsField);
  @field playerScore = contains(NumberField);
  @field dealerScore = contains(NumberField);
  @field dealerHand = containsMany(PlayingCardField);
  @field playerHand = containsMany(PlayingCardField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Blackjack) {
      return 'Blackjack';
    },
  });

  static isolated = IsolatedTemplate;
  static fitted = FittedTemplate;
}
