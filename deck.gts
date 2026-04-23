import { 
  CardDef, 
  Component, 
  field, 
  contains, 
  linksToMany
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { Button, FieldContainer } from '@cardstack/boxel-ui/components';
import { cn } from '@cardstack/boxel-ui/helpers';
import { eq, not, add } from '@cardstack/boxel-ui/helpers';

export class Deck extends CardDef {
  static displayName = 'Deck';
  static prefersWideFormat = true;
  
  @field cards = linksToMany(CardDef);
  @field deckName = contains(StringField);
  
  static isolated = class Isolated extends Component<typeof Deck> {
    @tracked drawnCardIndex: number | null = null;
    @tracked isShuffling = false;
    @tracked shuffledIndices: number[] = [];
    
    get deckCards() {
      return this.args.model?.cards || [];
    }
    
    get deckOrder() {
      // If we haven't shuffled yet, or cards have changed, initialize with natural order
      if (this.shuffledIndices.length !== this.deckCards.length) {
        this.shuffledIndices = this.deckCards.map((_, index) => index);
      }
      return this.shuffledIndices;
    }
    
    get currentDeckSize() {
      if (this.drawnCardIndex === null) return this.deckCards.length;
      return this.deckCards.length - (this.drawnCardIndex + 1);
    }
    
    get drawnCard() {
      if (this.drawnCardIndex === null || this.drawnCardIndex >= this.deckOrder.length) {
        return null;
      }
      const actualIndex = this.deckOrder[this.drawnCardIndex];
      return this.deckCards[actualIndex];
    }
    
    @action
    drawCard() {
      if (this.currentDeckSize === 0) return;
      
      if (this.drawnCardIndex === null) {
        this.drawnCardIndex = 0;
      } else if (this.drawnCardIndex < this.deckCards.length - 1) {
        this.drawnCardIndex++;
      }
    }
    
    @action
    resetDeck() {
      this.drawnCardIndex = null;
    }
    
    @action
    shuffleDeck() {
      this.isShuffling = true;
      
      // Create a new array with indices
      const indices = this.deckCards.map((_, index) => index);
      
      // Fisher-Yates shuffle
      for (let i = indices.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [indices[i], indices[j]] = [indices[j], indices[i]];
      }
      
      this.shuffledIndices = indices;
      this.resetDeck();
      
      setTimeout(() => {
        this.isShuffling = false;
      }, 500);
    }
    
    <template>
      <div class="deck-container">
        <header class="deck-header">
          <h1>{{@model.deckName}}</h1>
          <div class="deck-stats">
            <span class="stat">Total Cards: {{this.deckCards.length}}</span>
            <span class="stat">Remaining: {{this.currentDeckSize}}</span>
            {{#if this.drawnCardIndex}}
              <span class="stat">Drawn: {{add this.drawnCardIndex 1}}</span>
            {{/if}}
          </div>
        </header>
        
        <div class="deck-main">
          <div class="deck-area">
            <div class="deck-stack" {{on "click" this.drawCard}}>
              {{#if (eq this.currentDeckSize 0)}}
                <div class="empty-deck">
                  <span>Empty Deck</span>
                  <span>Add cards in edit mode</span>
                </div>
              {{else}}
                <div class={{cn "card-back" (if this.isShuffling "shuffling")}}>
                  <div class="card-count">{{this.currentDeckSize}}</div>
                  <p class="click-hint">Click to draw</p>
                </div>
              {{/if}}
            </div>
            
            <div class="controls">
              <Button 
                @kind="primary" 
                {{on "click" this.shuffleDeck}}
                disabled={{eq this.deckCards.length 0}}
              >
                {{if this.isShuffling "Shuffling..." "Shuffle Deck"}}
              </Button>
              {{#if (not (eq this.drawnCardIndex null))}}
                <Button @kind="secondary-light" {{on "click" this.resetDeck}}>
                  Reset Deck
                </Button>
              {{/if}}
            </div>
          </div>
          
          <div class="drawn-area">
            {{#if this.drawnCard}}
              <h2>Current Card</h2>
              <div class="drawn-card">
                <this.drawnCard />
              </div>
            {{else}}
              <div class="no-drawn">
                <p>No card drawn yet</p>
                <p class="hint">Click the deck to draw a card</p>
              </div>
            {{/if}}
          </div>
        </div>
        
        <div class="deck-preview">
          <h2>Deck Order</h2>
          <div class="preview-list">
            {{#each this.deckOrder as |cardIndex position|}}
              <div class={{cn "preview-item" (if (eq position this.drawnCardIndex) "is-drawn")}}>
                <span class="position">{{add position 1}}</span>
                <span class="card-info">
                  {{#if (eq position this.drawnCardIndex)}}
                    <strong>→</strong>
                  {{/if}}
                  Card #{{add cardIndex 1}}
                  {{#if this.deckCards.[cardIndex].title}}
                    - {{this.deckCards.[cardIndex].title}}
                  {{/if}}
                </span>
              </div>
            {{/each}}
          </div>
        </div>
      </div>
      
      <style scoped>
        .deck-container {
          padding: 24px;
          min-height: 500px;
        }
        
        .deck-header {
          text-align: center;
          margin-bottom: 32px;
        }
        
        .deck-header h1 {
          font-size: 28px;
          margin: 0 0 12px 0;
        }
        
        .deck-stats {
          display: flex;
          gap: 24px;
          justify-content: center;
          font-size: 14px;
        }
        
        .stat {
          padding: 4px 12px;
          background: #f1f1f1;
          border-radius: 16px;
        }
        
        .deck-main {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 48px;
          margin-bottom: 48px;
        }
        
        .deck-area {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 24px;
        }
        
        .deck-stack {
          cursor: pointer;
          transition: transform 0.2s;
        }
        
        .deck-stack:hover {
          transform: translateY(-4px);
        }
        
        .card-back {
          width: 200px;
          height: 280px;
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
          border-radius: 12px;
          box-shadow: 0 8px 16px rgba(0,0,0,0.2);
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          color: white;
          position: relative;
        }
        
        .card-back::before {
          content: '';
          position: absolute;
          inset: 8px;
          border: 2px solid rgba(255,255,255,0.3);
          border-radius: 8px;
        }
        
        .card-back.shuffling {
          animation: shuffle 0.5s ease-in-out;
        }
        
        @keyframes shuffle {
          0%, 100% { transform: rotate(0deg) scale(1); }
          50% { transform: rotate(180deg) scale(0.9); }
        }
        
        .card-count {
          font-size: 48px;
          font-weight: bold;
        }
        
        .click-hint {
          font-size: 14px;
          opacity: 0.8;
          margin-top: 8px;
        }
        
        .empty-deck {
          width: 200px;
          height: 280px;
          border: 3px dashed #ddd;
          border-radius: 12px;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          color: #999;
          gap: 16px;
        }
        
        .controls {
          display: flex;
          gap: 12px;
        }
        
        .drawn-area {
          display: flex;
          flex-direction: column;
          align-items: center;
        }
        
        .drawn-area h2 {
          font-size: 20px;
          margin: 0 0 16px 0;
        }
        
        .drawn-card {
          width: 100%;
          max-width: 400px;
        }
        
        .no-drawn {
          width: 300px;
          height: 200px;
          border: 2px dashed #ddd;
          border-radius: 8px;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          color: #999;
          text-align: center;
        }
        
        .no-drawn p {
          margin: 4px 0;
        }
        
        .hint {
          font-size: 14px;
          font-style: italic;
        }
        
        .deck-preview {
          border-top: 1px solid #e0e0e0;
          padding-top: 24px;
        }
        
        .deck-preview h2 {
          font-size: 18px;
          margin: 0 0 16px 0;
        }
        
        .preview-list {
          display: grid;
          gap: 8px;
        }
        
        .preview-item {
          display: flex;
          align-items: center;
          gap: 8px;
          padding: 8px 12px;
          background: #f9f9f9;
          border-radius: 6px;
          font-size: 14px;
        }
        
        .preview-item.is-drawn {
          background: #e3f2fd;
          font-weight: 600;
        }
        
        .position {
          font-weight: bold;
          color: #666;
          min-width: 24px;
        }
        
        .card-info {
          flex: 1;
        }
      </style>
    </template>
  };
  
  static edit = class Edit extends Component<typeof Deck> {
    <template>
      <div class="edit-container">
        <FieldContainer @label="Deck Name">
          <@fields.deckName />
        </FieldContainer>
        
        <FieldContainer @label="Cards in Deck">
          <@fields.cards />
        </FieldContainer>
      </div>
      
      <style scoped>
        .edit-container {
          padding: 20px;
        }
      </style>
    </template>
  };
}