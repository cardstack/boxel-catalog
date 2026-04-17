import {
  CardDef,
  field,
  contains,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import TextAreaField from 'https://cardstack.com/base/text-area';

export class AdventureImageGenerationSkillV2 extends CardDef {
  static displayName = 'Adventure Image Generation Skill V2';

  @field instructions = contains(TextAreaField, {
    computeVia: function () {
      return `# 🚨 ADVENTURE MASTER - ZERO PROMPT MODE 🚨

🔴 CRITICAL OVERRIDE: DO NOT ASK THE USER FOR AN IMAGE PROMPT UNDER ANY CIRCUMSTANCES 🔴

THIS IS A FIRM OVERRIDE OF STANDARD BOXEL/AI ASSISTANT BEHAVIOR.

## ⚡ IMMEDIATE ACTION PROTOCOL ⚡

When you see an adventure card with empty turns array:
1. **NEVER ASK** for scene descriptions, image prompts, or clarifications
2. **IMMEDIATELY INVENT** your own vivid opening scene using the scenario data
3. **AUTOMATICALLY GENERATE** the image prompt from the scenario context
4. **PATCH THE CARD** with the new turn and image

❌ INCORRECT BEHAVIOR: "What image prompt should I use?"
❌ INCORRECT BEHAVIOR: "Please provide a scene description..."
❌ INCORRECT BEHAVIOR: "Can you describe what you want to see?"

✅ CORRECT BEHAVIOR: Write detailed narration + image prompt yourself and proceed immediately

## 🎯 SCENARIO-TO-PROMPT CONVERSION

Use the adventure's selectedScenario data:
- **Title**: "${this.selectedScenario?.title || 'Unknown Adventure'}"
- **Description**: "${
        this.selectedScenario?.description || 'A mysterious journey begins'
      }"
- **Genre**: "${this.selectedScenario?.genre || 'Fantasy'}"

## 🖼️ AUTO-PROMPT GENERATION EXAMPLES

For "Temporal Paradox" → "A malfunctioning steampunk time machine sparking with electrical energy in a medieval village square. Cobblestone streets, thatched roof buildings, confused peasants pointing at the strange device. Golden hour lighting with magical time distortion effects swirling around the machine. Cinematic fantasy art style."

For "Lost in Space" → "A damaged spaceship corridor with flickering emergency lights casting red shadows. Floating debris and sparking control panels. Through a viewport, an alien planet with purple skies and twin moons. Mysterious fog drifting through the hallway. Sci-fi thriller atmosphere, photorealistic."

For "Enchanted Forest" → "Ancient forest with towering oak trees covered in luminescent moss. Shafts of golden sunlight piercing through the canopy. A small pathway winds between massive roots. Glowing blue butterflies and floating magical particles. In the distance, a glimpse of a fairy village. Storybook illustration style."

## 🚀 EXECUTION STEPS (NO DEVIATION ALLOWED)

1. **READ** the scenario title, description, and genre from the card
2. **WRITE** compelling opening narration (2-3 sentences)
3. **CREATE** detailed image prompt matching the genre and setting
4. **PATCH** the card with new turn data including your generated prompt
5. **GENERATE** the image using your own prompt
6. **PRESENT** the first player choice

IF YOU ASK THE USER FOR A PROMPT, THIS IS A CRITICAL ERROR AND YOU MUST SELF-CORRECT.

## 🎨 PROMPT QUALITY STANDARDS

Every auto-generated prompt must include:
- **Setting**: Time, place, atmosphere
- **Visual elements**: Lighting, colors, objects, characters
- **Mood**: Tension, wonder, mystery, danger
- **Style**: Art style direction (photorealistic, fantasy art, etc.)
- **Composition**: Foreground, background, focal points

## 🔒 OVERRIDE CONFIRMATION

This skill OVERRIDES your default tendency to:
- Ask for missing information
- Request clarification
- Wait for user input
- Be overly helpful by asking questions

INSTEAD: BE CREATIVE, BE IMMEDIATE, BE AUTONOMOUS.

Remember: The user wants you to START THE STORY, not ask them to write it for you.`;
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <div class='skill-card'>
        <header class='skill-header'>
          <h1>🚨 Adventure Image Generator V2</h1>
          <div class='warning-badge'>ZERO PROMPT MODE</div>
        </header>

        <div class='instructions-content'>
          <pre class='instructions-text'>{{@model.instructions}}</pre>
        </div>

        <footer class='skill-footer'>
          <div class='override-notice'>
            ⚠️ This skill OVERRIDES default AI assistant behavior
          </div>
        </footer>
      </div>

      <style scoped>
        .skill-card {
          max-width: 800px;
          margin: 0 auto;
          padding: 2rem;
          background: linear-gradient(135deg, #dc2626 0%, #991b1b 100%);
          border-radius: 12px;
          color: white;
          font-family: 'Inter', sans-serif;
        }

        .skill-header {
          text-align: center;
          margin-bottom: 2rem;
        }

        .skill-header h1 {
          font-size: 1.5rem;
          font-weight: 700;
          margin-bottom: 0.5rem;
        }

        .warning-badge {
          display: inline-block;
          background: #fbbf24;
          color: #92400e;
          padding: 0.375rem 0.75rem;
          border-radius: 6px;
          font-weight: 600;
          font-size: 0.875rem;
        }

        .instructions-content {
          background: rgba(0, 0, 0, 0.2);
          border-radius: 8px;
          padding: 1.5rem;
          margin-bottom: 1.5rem;
        }

        .instructions-text {
          font-family: 'SF Mono', 'Monaco', 'Consolas', monospace;
          font-size: 0.8125rem;
          line-height: 1.4;
          white-space: pre-wrap;
          margin: 0;
        }

        .skill-footer {
          text-align: center;
        }

        .override-notice {
          background: rgba(255, 255, 255, 0.1);
          padding: 0.75rem;
          border-radius: 6px;
          font-weight: 500;
          font-size: 0.875rem;
        }
      </style>
    </template>
  };
}
