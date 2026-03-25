import {
  CardDef,
  Component,
  field,
  contains,
  StringField,
} from 'https://cardstack.com/base/card-api';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { on } from '@ember/modifier';

// Define card suits and values
const SUITS = ['♥', '♦', '♣', '♠'];
const VALUES = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];

// Card class for playing cards
class PlayingCard {
  suit: string;
  value: string;
  
  constructor(suit: string, value: string) {
    this.suit = suit;
    this.value = value;
  }

  get color(): string {
    return this.suit === '♥' || this.suit === '♦' ? 'red' : 'black';
  }

  get display(): string {
    return `${this.value}${this.suit}`;
  }
}

export class SimpleCardDeck extends CardDef {
  static displayName = 'Simple Card Deck';
  
  @field cardTitle = contains(StringField);

  static isolated = class Isolated extends Component<typeof SimpleCardDeck> {
    @tracked deck: PlayingCard[] = [];
    @tracked drawnCards: PlayingCard[] = [];
    @tracked isLoading = true;
    @tracked selectedCard: PlayingCard | null = null;
    @tracked showCardDialog = false;
    @tracked drawButtonDisabled = false;
    @tracked resetButtonDisabled = true;
    @tracked currentCardIndex = -1; // For tracking selected card index

    constructor(owner: unknown, args: any) {
      super(owner, args);
      this.initializeDeck();
    }

    initializeDeck() {
      this.isLoading = true;
      
      // Generate a standard deck of cards
      const newDeck: PlayingCard[] = [];
      for (const suit of SUITS) {
        for (const value of VALUES) {
          newDeck.push(new PlayingCard(suit, value));
        }
      }
      
      // Shuffle the deck
      this.deck = this.shuffleDeck([...newDeck]);
      this.drawnCards = [];
      
      this.drawButtonDisabled = false;
      this.resetButtonDisabled = true;
      this.isLoading = false;
    }
    
    shuffleDeck(cards: PlayingCard[]): PlayingCard[] {
      for (let i = cards.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [cards[i], cards[j]] = [cards[j], cards[i]];
      }
      return cards;
    }

    // Draw a card from the deck
    @action drawCard() {
      if (this.deck.length === 0) {
        return;
      }
      
      // Draw a card from the top of the deck
      const drawnCard = this.deck.pop()!;
      this.drawnCards = [drawnCard, ...this.drawnCards];
      
      // Update button states
      if (this.deck.length === 0) {
        this.drawButtonDisabled = true;
      }
      
      this.resetButtonDisabled = false;
    }

    // Reset the deck
    @action resetDeck() {
      this.initializeDeck();
    }

    // View a card in detail - now with index parameter
    @action handleCardClick(index: number) {
      this.selectedCard = this.drawnCards[index];
      this.showCardDialog = true;
    }

    // Close the card dialog
    @action closeDialog() {
      this.showCardDialog = false;
    }
    
    // Stop propagation
    @action stopPropagation(e: Event) {
      e.stopPropagation();
    }

    <template>
      <div class="simulator">
        <h1>Simple Card Deck</h1>
        
        {{#if this.isLoading}}
          <div class="loading">Shuffling cards...</div>
        {{else}}
          <div class="content">
            <div class="deck-area">
              <div class="deck" {{on "click" this.drawCard}}>
                <div class="deck-count">{{this.deck.length}}</div>
                <div class="deck-label">cards remaining</div>
              </div>
              <div class="actions">
                <button {{on "click" this.drawCard}} disabled={{this.drawButtonDisabled}}>
                  Draw Card
                </button>
                <button {{on "click" this.resetDeck}} disabled={{this.resetButtonDisabled}}>
                  Reset Deck
                </button>
              </div>
            </div>

            <div class="drawn-area">
              <h2>Drawn Cards ({{this.drawnCards.length}})</h2>
              {{#if this.drawnCards.length}}
                <div class="cards-grid">
                  {{#each this.drawnCards as |card index|}}
                    <div class="card-item" {{on "click" (action this.handleCardClick index)}}>
                      <div class="playing-card" style="color: {{card.color}};">
                        <div class="card-corner top-left">
                          <div class="card-value">{{card.value}}</div>
                          <div class="card-suit">{{card.suit}}</div>
                        </div>
                        <div class="card-center">{{card.suit}}</div>
                        <div class="card-corner bottom-right">
                          <div class="card-value">{{card.value}}</div>
                          <div class="card-suit">{{card.suit}}</div>
                        </div>
                      </div>
                    </div>
                  {{/each}}
                </div>
              {{else}}
                <p>No cards drawn yet. Click the deck to draw a card.</p>
              {{/if}}
            </div>
          </div>

          {{#if this.showCardDialog}}
            <div class="dialog-overlay" {{on "click" this.closeDialog}}>
              <div class="dialog" {{on "click" this.stopPropagation}}>
                <button class="close-button" {{on "click" this.closeDialog}}>×</button>
                {{#if this.selectedCard}}
                  <div class="card-detail">
                    <div class="playing-card large" style="color: {{this.selectedCard.color}};">
                      <div class="card-corner top-left">
                        <div class="card-value">{{this.selectedCard.value}}</div>
                        <div class="card-suit">{{this.selectedCard.suit}}</div>
                      </div>
                      <div class="card-center large-suit">{{this.selectedCard.suit}}</div>
                      <div class="card-corner bottom-right">
                        <div class="card-value">{{this.selectedCard.value}}</div>
                        <div class="card-suit">{{this.selectedCard.suit}}</div>
                      </div>
                    </div>
                  </div>
                {{/if}}
              </div>
            </div>
          {{/if}}
        {{/if}}
      </div>

      <style scoped>
        .simulator {
          display: flex;
          flex-direction: column;
          padding: 20px;
          height: 100%;
          background-color: #f5f5f5;
          font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        }

        h1 {
          font-size: 24px;
          margin-bottom: 20px;
        }

        h2 {
          font-size: 18px;
          margin-bottom: 10px;
        }

        .loading {
          display: flex;
          justify-content: center;
          align-items: center;
          height: 200px;
          font-size: 18px;
        }

        .content {
          display: grid;
          grid-template-columns: 250px 1fr;
          gap: 30px;
        }

        .deck {
          width: 200px;
          height: 280px;
          background-color: #284b63;
          border-radius: 10px;
          box-shadow: 
            0 1px 1px rgba(0,0,0,0.05),
            0 2px 2px rgba(0,0,0,0.05),
            0 4px 4px rgba(0,0,0,0.05),
            0 8px 8px rgba(0,0,0,0.05),
            0 16px 16px rgba(0,0,0,0.05);
          display: flex;
          flex-direction: column;
          justify-content: center;
          align-items: center;
          position: relative;
          cursor: pointer;
          margin-bottom: 20px;
          transition: transform 0.2s ease, box-shadow 0.2s ease;
        }

        .deck:hover {
          transform: translateY(-5px);
          box-shadow: 
            0 2px 2px rgba(0,0,0,0.1),
            0 4px 4px rgba(0,0,0,0.1),
            0 8px 8px rgba(0,0,0,0.1),
            0 16px 16px rgba(0,0,0,0.1),
            0 32px 32px rgba(0,0,0,0.1);
        }

        .deck:before {
          content: '';
          position: absolute;
          top: 0;
          left: 0;
          width: 100%;
          height: 100%;
          background-image: 
            radial-gradient(circle at 10% 10%, rgba(255,255,255,0.1) 0%, transparent 30%),
            linear-gradient(to bottom right, rgba(255,255,255,0.05) 0%, transparent 70%);
          border-radius: 10px;
        }

        .count {
          font-size: 48px;
          font-weight: 700;
          color: white;
          z-index: 1;
        }

        .label {
          font-size: 16px;
          color: white;
          z-index: 1;
        }

        .actions {
          display: flex;
          gap: 10px;
        }

        button {
          padding: 8px 16px;
          border-radius: 4px;
          border: none;
          cursor: pointer;
          flex-grow: 1;
        }

        button:first-child {
          background-color: #3c6e71;
          color: white;
        }

        button:last-child {
          background-color: #d9d9d9;
        }

        button[disabled] {
          opacity: 0.5;
          cursor: not-allowed;
        }

        .cards-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
          gap: 16px;
        }

        .card-item {
          height: 200px;
          border-radius: 8px;
          overflow: hidden;
          transition: transform 0.2s;
          cursor: pointer;
        }

        .card-item:hover {
          transform: translateY(-3px);
          box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }

        .playing-card {
          position: relative;
          width: 100%;
          height: 100%;
          background-color: white;
          border-radius: 8px;
          box-shadow: 0 2px 4px rgba(0,0,0,0.1);
          display: flex;
          justify-content: center;
          align-items: center;
        }

        .card-corner {
          position: absolute;
          display: flex;
          flex-direction: column;
          align-items: center;
          line-height: 1;
        }

        .top-left {
          top: 8px;
          left: 8px;
        }

        .bottom-right {
          bottom: 8px;
          right: 8px;
          transform: rotate(180deg);
        }

        .card-value {
          font-size: 20px;
          font-weight: bold;
        }

        .card-suit {
          font-size: 20px;
        }

        .card-center {
          font-size: 60px;
        }

        .large-suit {
          font-size: 120px;
        }

        .dialog-overlay {
          position: fixed;
          top: 0;
          left: 0;
          width: 100%;
          height: 100%;
          background-color: rgba(0,0,0,0.5);
          display: flex;
          justify-content: center;
          align-items: center;
          z-index: 100;
        }

        .dialog {
          width: 300px;
          height: 420px;
          background-color: white;
          border-radius: 8px;
          position: relative;
          overflow: hidden;
          padding: 10px;
        }

        .close-button {
          position: absolute;
          top: 10px;
          right: 10px;
          width: 30px;
          height: 30px;
          border-radius: 50%;
          display: flex;
          justify-content: center;
          align-items: center;
          background-color: rgba(0,0,0,0.1);
          z-index: 10;
          font-size: 20px;
          cursor: pointer;
        }

        .card-detail {
          width: 100%;
          height: 100%;
          display: flex;
          justify-content: center;
          align-items: center;
        }

        .playing-card.large {
          width: 240px;
          height: 336px;
          border-radius: 16px;
          box-shadow: 0 10px 30px rgba(0,0,0,0.2);
        }

        .playing-card.large .card-value {
          font-size: 40px;
        }

        .playing-card.large .card-suit {
          font-size: 40px;
        }
      </style>
    </template>
  }
} 