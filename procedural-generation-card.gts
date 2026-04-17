import { CardDef, Component, field, contains } from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import { FieldContainer } from '@cardstack/boxel-ui/components';

// Word lists for procedural phrase generation
const ADJECTIVES = ["Agile", "Bold", "Calm", "Daring", "Eager", "Fancy", "Giant", "Happy", "Icy", "Jolly"];
const NOUNS = ["Lion", "Tiger", "Bear", "Eagle", "Shark", "Wolf", "Robot", "Wizard", "Planet", "Ocean"];
const VERBS = ["Jumps", "Sleeps", "Flies", "Swims", "Hunts", "Roars", "Dreams", "Thinks", "Explores", "Listens"];
const ADVERBS = ["Quickly", "Slowly", "Loudly", "Quietly", "Bravely", "Gently", "Joyfully", "Wisely", "Eagerly", "Calmly"];

export class ProceduralGenerationCard extends CardDef {
  static displayName = "Procedural Generation Demo";

  @field seed = contains(StringField);

  @field generatedPhrase = contains(StringField, {
    computeVia: function(this: ProceduralGenerationCard) {
      try {
        if (!this.seed || this.seed.trim() === "") {
          return "Enter a seed above to generate a phrase!";
        }

        let numericSeed = 0;
        // Create a numeric hash from the seed string
        for (let i = 0; i < this.seed.length; i++) {
          numericSeed = (numericSeed * 31 + this.seed.charCodeAt(i)) & 0xFFFFFFFF; // Keep it a 32-bit int
        }
        numericSeed = Math.abs(numericSeed); // Ensure positive
        if (numericSeed === 0) numericSeed = 1; // LCG should not start with 0 if c=0

        // LCG Parameters (Park-Miller pseudo-random number generator)
        const m = 2147483647; // Modulus (2^31 - 1, a Mersenne prime)
        const a = 48271;      // Multiplier
        // c (increment) is 0 for this version (multiplicative congruential generator)

        let x = numericSeed;

        // Helper to get a pseudo-random number in [0, 1) and update state x
        const nextRandom = () => {
          x = (a * x) % m;
          if (x === 0) x = 1; // Prevent getting stuck at 0;
          return x / m;
        };

        const adjIndex = Math.floor(nextRandom() * ADJECTIVES.length);
        const nounIndex = Math.floor(nextRandom() * NOUNS.length);
        const verbIndex = Math.floor(nextRandom() * VERBS.length);
        const adverbIndex = Math.floor(nextRandom() * ADVERBS.length);

        return `${ADJECTIVES[adjIndex]} ${NOUNS[nounIndex]} ${VERBS[verbIndex]} ${ADVERBS[adverbIndex]}.`;
      } catch (e) {
        console.error("Error in procedural generation:", e);
        return "Error generating phrase. See console for details.";
      }
    }
  });

  static isolated = class Isolated extends Component<typeof ProceduralGenerationCard> {
    <template>
      <div class="procedural-card">
        <div class="seed-display">
          <strong>Seed:</strong> <span class="seed-value">{{@model.seed}}</span>
        </div>
        <div class="output-area">
          <p class="generated-text-label">Generated Phrase:</p>
          <p class="generated-text">{{@model.generatedPhrase}}</p>
        </div>
        <div class="explanation">
          <p>Edit this card to change the seed and see the generated phrase update. The same seed will always produce the same phrase.</p>
        </div>
      </div>
      <style scoped>
        .procedural-card {
          padding: 20px;
          font-family: sans-serif;
          background-color: #f9f9f9;
          border-radius: 8px;
          box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .seed-display {
          margin-bottom: 15px;
          padding: 10px;
          background-color: #e9e9e9;
          border-radius: 4px;
        }
        .seed-value {
          font-family: monospace;
          background-color: #fff;
          padding: 2px 5px;
          border-radius: 3px;
        }
        .output-area {
          margin-bottom: 20px;
          padding: 15px;
          background-color: #ffffff;
          border: 1px solid #ddd;
          border-radius: 4px;
        }
        .generated-text-label {
          font-weight: bold;
          margin-bottom: 5px;
          color: #333;
        }
        .generated-text {
          font-size: 1.2em;
          color: #555;
          min-height: 1.5em; /* Ensure space even when empty */
          font-style: italic;
        }
        .explanation {
          font-size: 0.9em;
          color: #777;
          border-top: 1px solid #eee;
          padding-top: 15px;
          margin-top: 15px;
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof ProceduralGenerationCard> {
    <template>
      <div class="procedural-card-edit">
        <FieldContainer @label="Enter Seed">
          <@fields.seed />
        </FieldContainer>
        <div class="output-area-edit">
          <p class="generated-text-label">Generated Phrase:</p>
          <p class="generated-text">{{@model.generatedPhrase}}</p>
        </div>
      </div>
      <style scoped>
        .procedural-card-edit {
          padding: 20px;
          font-family: sans-serif;
        }
        /* Target the div wrapper Boxel adds around the input for FieldContainer */
        .procedural-card-edit > div:first-child {
          margin-bottom: 20px;
        }
        .output-area-edit {
          margin-top: 20px;
          padding: 15px;
          background-color: #f9f9f9;
          border: 1px solid #ddd;
          border-radius: 4px;
        }
        .generated-text-label {
          font-weight: bold;
          margin-bottom: 5px;
          color: #333;
        }
        .generated-text {
          font-size: 1.2em;
          color: #555;
          min-height: 1.5em; /* Ensure space even when empty */
          font-style: italic;
        }
      </style>
    </template>
  };
}