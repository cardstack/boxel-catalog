 // ═══ [EDIT TRACKING: ON] Mark all changes with ⁽¹⁾ ═══
import { fn, get } from '@ember/helper';
import { on } from '@ember/modifier';
import { gt } from '@cardstack/boxel-ui/helpers';
// ⁽¹⁾ CardDef/fields
import { CardDef, field, containsMany, contains, Component } from 'https://cardstack.com/base/card-api';
// ⁽²⁾ For deck name/title
import StringField from 'https://cardstack.com/base/string';
// ⁽³⁾ Our entry type
import { DeckEntryField } from './deck-entry-field.gts';
// ⁽⁴⁾ UI
import { Button, CardContainer } from '@cardstack/boxel-ui/components';
// ⁽⁵⁾ Shuffle icon
import ShuffleIcon from '@cardstack/boxel-icons/shuffle';
import { tracked } from '@glimmer/tracking';

// Utility for array shuffling
// Defining custom helper - not yet available in Boxel environment
function shuffleArray<T>(array: T[]): T[] {
  let a = [...array];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

// ⁽⁶⁾ Deck Card definition
export class DeckCardTwo extends CardDef {
  static displayName = 'Deck 2';
  static icon = ShuffleIcon; // ⁽⁷⁾
  static prefersWideFormat = true; // wider layout for better UI

  @field deckName = contains(StringField); // Optional deck name
  @field entries = containsMany(DeckEntryField); // The deck (ordered, allows duplicates)

  // Compute title
  @field cardTitle = contains(StringField, {
    computeVia: function(this: DeckCardTwo) {
      return this.deckName || `Deck (${(this.entries?.length || 0)} cards)`; // Fallback
    }
  });

  // Isolated format (main deck UI)
  static isolated = class Isolated extends Component<typeof DeckCardTwo> {
    // State: top card drawn? index of drawn card
    @tracked drawnIndex?: number = undefined;

    // Draw top card (set drawnIndex = 0)
    drawTop = () => {
      if (this.entriesLength > 0) {
        this.drawnIndex = 0;
      }
    };

    // Shuffle deck and clear drawn card
    shuffleDeck = () => {
      const entriesArr = Array.isArray(this.args?.model?.entries) ? [...this.args.model.entries] : [];
      const shuffled = shuffleArray(entriesArr);
      this.args.model.entries = shuffled; // Will re-render
      this.drawnIndex = undefined;
    };

    // Put back drawn card (clear drawnIndex)
    putBack = () => {
      this.drawnIndex = undefined;
    };

    // Total card count
    get entriesLength() {
      return Array.isArray(this.args?.model?.entries) ? this.args.model.entries.length : 0;
    }

    // Unique card type count
    get uniqueTypesCount() {
      try {
        if (!Array.isArray(this.args?.model?.entries)) return 0;
        const seen = new Set();
        this.args.model.entries.forEach(entry => {
          let t = entry.cardRef?.title || '';
          seen.add(t);
        });
        return seen.size;
      } catch { return 0; }
    }

    // Fallback for deck name
    get safeDeckName() {
      return this.args?.model?.deckName || 'Deck';
    }

    // Entry display for summary
    get entrySummary() {
      return `${this.entriesLength} cards, ${this.uniqueTypesCount} unique`;
    }

  // Drawn card (top card)
  get drawnEntry() {
    if (typeof this.drawnIndex === 'number' && this.entriesLength > 0) {
      return this.args.model.entries[this.drawnIndex];
    }
    return null;
  }

  <template>
    <div class="deck-stage">
      <div class="deck-mat">

        <header class="deck-header">
          <h1 class="deck-name">{{this.safeDeckName}}</h1>
        </header>

        <!-- Deck UI: Stack with cards face down -->
        {{#if (gt this.entriesLength 0)}}
          <section class="deck-stack-section">
            <CardContainer
              class="deck-stack"
              @displayBoundaries={{true}}
              {{on "click" this.drawTop}}
              title="Click to draw top card"
            >
              <div class="deck-stack-face">
                <div class="stack-count">{{this.entriesLength}}</div>
                <div class="stack-label">cards</div>
              </div>
            </CardContainer>
          </section>
        {{else}}
          <div class="empty-state">
            <p>No cards in deck. Add cards to build your deck!</p>
          </div>
        {{/if}}

        <!-- Drawn card area: show fitted format of the top card when drawn -->
        {{#if this.drawnEntry}}
          <div class="drawn-card-area">
            <h3>Drawn Card</h3>
            <CardContainer class="drawn-card" @displayBoundaries={{true}}>
              {{#let @fields.entries as |entriesField|}}
                {{#let (get entriesField this.drawnIndex) as |drawnField|}}
                  {{#if drawnField}}
                    <drawnField.cardRef @format="fitted" style="width: 100%; height: 100%" />
                  {{else}}
                    <div class="empty-card">Card not found</div>
                  {{/if}}
                {{/let}}
              {{/let}}
            </CardContainer>
            <Button @variant="ghost" {{on "click" this.putBack}}>
              Put Back
            </Button>
          </div>
        {{/if}}

          <!-- Totals row -->
          <div class="totals-row">
            <span>{{this.entrySummary}}</span>
            <Button @variant="primary" @icon={{ShuffleIcon}} @size="sm" {{on "click" this.shuffleDeck}}>
              Shuffle Deck
            </Button>
          </div>
        </div>
      </div>
      <style scoped>
        .deck-stage {
          width: 100%;
          height: 100%;
          display: flex;
          justify-content: center;
          padding: 1.5rem 0.5rem;
          background: linear-gradient(135deg, #e8eaf6 10%, #fff 100%);
        }
        .deck-mat {
          width: 100%;
          max-width: 375px;
          background: #fff;
          border-radius: 1rem;
          box-shadow: 0 12px 36px -8px rgba(0,0,0,0.09);
          overflow-y: auto;
          padding: 1.25rem 1.5rem;
        }
        .deck-header {
          margin-bottom: 0.75rem;
        }
        .deck-name {
          font-size: 1.4rem;
          margin: 0 0 0.5rem 0;
          font-weight: bold;
          text-align: center;
        }
        .deck-stack-section {
          display: flex;
          justify-content: center;
          padding: 1.15rem 0 1rem 0;
        }
        .deck-stack {
          cursor: pointer;
          width: 100px;
          min-height: 120px;
          border-radius: 0.8rem;
          border: 2.5px solid #5b82ee;
          box-shadow: 0 1.7px 9px 1.2px #bae3fa58;
          background: linear-gradient(160deg, #dbeafe 90%, #fff 100%);
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          transition: box-shadow 0.14s, border-color 0.14s;
        }
        .deck-stack:hover {
          box-shadow: 0 4px 20px 2px #5b82ee1c;
          border-color: #ed99fa;
        }
        .deck-stack-face {
          padding-top: 10px;
          padding-bottom: 16px;
          text-align: center;
        }
        .stack-count {
          font-size: 2.5rem;
          color: #4562a0;
          font-weight: 700;
        }
        .stack-label {
          color: #7e818c;
          font-size: 0.95rem;
        }
        .drawn-card-area {
          margin: 1.5rem 0 1.25rem 0;
          text-align: center;
        }
        .drawn-card {
          margin: 0 auto 0.65rem auto;
          min-height: 80px;
          min-width: 100px;
          max-width: 193px;
          border-radius: 0.65rem;
        }
        .empty-card {
          color: #9ca3af;
          font-style: italic;
          text-align: center;
          padding: 2rem 0.5rem;
        }
        .totals-row {
          margin-top: 1.5rem;
          margin-bottom: 0.7rem;
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 1.7rem;
          font-size: 1rem;
          font-weight: 500;
        }
        .empty-state {
          text-align: center;
          color: #7b8797;
          margin: 1.5rem 0;
        }
      </style>
    </template>
  };
}