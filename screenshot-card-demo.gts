import {
  CardDef,
  Component,
  contains,
  field,
  linksToMany,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import enumField from 'https://cardstack.com/base/enum';
import { action } from '@ember/object';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';

import ScreenshotCardCommand from '@cardstack/boxel-host/commands/screenshot-card';
import { Button } from '@cardstack/boxel-ui/components';

type ScreenshotFormat = 'isolated' | 'embedded';

interface ScreenshotResult {
  id: string;
  title: string;
  imageDefUrl?: string;
  error?: string;
}

// Built-in enum field — atom view shows the current value as plain text;
// edit view renders a BoxelSelect dropdown of the configured options.
const FormatField = enumField(StringField, {
  options: ['isolated', 'embedded'],
  displayName: 'Screenshot Format',
});

class Isolated extends Component<typeof ScreenshotCardDemo> {
  @tracked isRunning = false;
  @tracked errorMessage: string | null = null;
  @tracked results: ScreenshotResult[] = [];
  @tracked processedCount = 0;

  get hasCommandContext() {
    return Boolean(this.args.context?.commandContext);
  }

  get linkedCards(): any[] {
    let cards = (this.args.model as any)?.cards;
    return Array.isArray(cards) ? cards.filter((c) => Boolean(c?.id)) : [];
  }

  get hasLinkedCards() {
    return this.linkedCards.length > 0;
  }

  get isDisabled() {
    return this.isRunning || !this.hasCommandContext || !this.hasLinkedCards;
  }

  get effectiveFormat(): ScreenshotFormat {
    let raw = (this.args.model as any)?.format?.trim?.();
    return raw === 'embedded' ? 'embedded' : 'isolated';
  }

  get buttonLabel() {
    if (this.isRunning) {
      return `Taking screenshots… ${this.processedCount}/${this.linkedCards.length}`;
    }
    let count = this.linkedCards.length;
    return count > 1 ? `Take ${count} Screenshots` : 'Take Screenshot';
  }

  @action
  async takeScreenshots() {
    let commandContext = this.args.context?.commandContext;
    let cards = this.linkedCards;
    if (!commandContext) {
      this.errorMessage =
        'Command context is unavailable. Open this card in host interact mode.';
      return;
    }
    if (!cards.length) {
      this.errorMessage = 'Link at least one card before taking screenshots.';
      return;
    }

    this.isRunning = true;
    this.errorMessage = null;
    this.results = [];
    this.processedCount = 0;

    let collected: ScreenshotResult[] = [];
    for (let card of cards) {
      let title = card?.title ?? card?.id ?? 'Untitled';
      try {
        let result = await new ScreenshotCardCommand(commandContext).execute({
          card,
          format: this.effectiveFormat,
        });
        collected = [
          ...collected,
          { id: card.id, title, imageDefUrl: result.imageDefUrl },
        ];
      } catch (error) {
        collected = [
          ...collected,
          {
            id: card?.id ?? title,
            title,
            error: error instanceof Error ? error.message : String(error),
          },
        ];
      }
      this.processedCount = collected.length;
      this.results = collected;
    }

    this.isRunning = false;
  }

  <template>
    <article class='screenshot-card-demo'>
      <header>
        <h2>Screenshot Card Demo</h2>
        <p>
          Link one or more cards and pick a format, then capture a settled PNG
          for each into its own realm under
          <code>Screenshots/</code>.
        </p>
      </header>

      <section class='field'>
        <label>Cards to screenshot</label>
        <@fields.cards />
      </section>

      <section class='field'>
        <label>Format</label>
        <@fields.format />
      </section>

      <section class='actions'>
        <Button
          data-test-take-screenshot
          @disabled={{this.isDisabled}}
          {{on 'click' this.takeScreenshots}}
        >
          {{this.buttonLabel}}
        </Button>
      </section>

      {{#if this.results.length}}
        <section class='results'>
          {{#each this.results as |result|}}
            <div class='result'>
              <p class='result-title'>{{result.title}}</p>
              {{#if result.imageDefUrl}}
                <code class='url'>{{result.imageDefUrl}}</code>
                <img src={{result.imageDefUrl}} alt='Card screenshot' />
              {{else}}
                <p class='status status--error'>{{result.error}}</p>
              {{/if}}
            </div>
          {{/each}}
        </section>
      {{/if}}

      {{#if this.errorMessage}}
        <p class='status status--error'>{{this.errorMessage}}</p>
      {{/if}}
    </article>

    <style scoped>
      .screenshot-card-demo {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-lg);
        padding: var(--boxel-sp-lg);
      }
      header p {
        margin: var(--boxel-sp-xs) 0 0;
        color: var(--boxel-700);
      }
      .field {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
      }
      .field label {
        font-weight: 600;
      }
      .actions {
        display: flex;
        gap: var(--boxel-sp);
      }
      .results {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
      }
      .result {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp);
        border: 1px solid var(--boxel-200);
        border-radius: var(--boxel-border-radius-lg);
        background: var(--boxel-50);
      }
      .result-title {
        margin: 0;
        font-weight: 600;
      }
      .result img {
        max-width: 100%;
        border: 1px solid var(--boxel-200);
        border-radius: var(--boxel-border-radius);
      }
      .url {
        word-break: break-all;
        font-size: var(--boxel-font-sm);
      }
      .status {
        margin: 0;
        padding: var(--boxel-sp-sm);
        border-radius: var(--boxel-border-radius);
      }
      .status--error {
        background: color-mix(in srgb, var(--boxel-error-100) 12%, white);
        color: var(--boxel-error-100);
      }
    </style>
  </template>
}

export class ScreenshotCardDemo extends CardDef {
  static displayName = 'Screenshot Card Demo';

  @field cards = linksToMany(CardDef);
  @field format = contains(FormatField);

  static isolated = Isolated;
}
