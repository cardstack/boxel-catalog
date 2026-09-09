import { CardDef, Component, contains, field } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import CodeSnippet from '../../../components/code-snippet';
import AspectRatioField, { ASPECT_RATIO_OPTIONS } from '../aspect-ratio';

const usageCode = `import AspectRatioField from '@cardstack/catalog/fields/aspect-ratio/aspect-ratio';

@field aspectRatio = contains(AspectRatioField);`;

export class AspectRatioExample extends CardDef {
  static displayName = 'Aspect Ratio Example';

  @field aspectRatio = contains(AspectRatioField);
  @field title = contains(StringField);
  @field description = contains(StringField);

  static isolated = class Isolated extends Component<typeof this> {
    options = ASPECT_RATIO_OPTIONS;

    <template>
      <article class='field-example'>
        <header class='fe-header'>
          <span class='fe-eyebrow'>Field Example</span>
          <h1 class='fe-title'>{{@model.title}}</h1>
          {{#if @model.description}}
            <p class='fe-desc'>{{@model.description}}</p>
          {{/if}}
        </header>

        <section class='fe-panel'>
          <div class='fe-panel-head'>
            <span class='fe-panel-label'>Interactive</span>
            <span class='fe-panel-hint'>Pick a ratio</span>
          </div>
          <div class='fe-panel-body'>
            <@fields.aspectRatio @format='edit' />
          </div>
        </section>

        <section class='fe-panel'>
          <div class='fe-panel-head'>
            <span class='fe-panel-label'>Preview</span>
            <span class='fe-panel-hint'>Read-only value</span>
          </div>
          <div class='fe-panel-body'>
            <@fields.aspectRatio />
          </div>
        </section>

        <section class='fe-panel'>
          <div class='fe-panel-head'>
            <span class='fe-panel-label'>Available ratios</span>
          </div>
          <p class='fe-api-intro'>Exported as ASPECT_RATIO_OPTIONS by the field.</p>
          <div class='fe-api'>
            <div class='fe-api-row fe-api-row--head'>
              <span>Value</span>
              <span>Orientation</span>
            </div>
            {{#each this.options as |opt|}}
              <div class='fe-api-row'>
                <code class='fe-api-name'>{{opt.value}}</code>
                <span class='fe-api-type'>{{opt.orientation}}</span>
              </div>
            {{/each}}
          </div>
        </section>

        <section class='fe-panel fe-panel--code'>
          <div class='fe-panel-head'>
            <span class='fe-panel-label'>Usage</span>
          </div>
          <CodeSnippet @code={{usageCode}} />
        </section>
      </article>
      <style scoped>
        .field-example {
          display: grid;
          gap: var(--boxel-sp);
          max-width: 42.5rem;
          margin-inline: auto;
          padding: var(--boxel-sp-lg);
          font-family: var(--boxel-font-family);
          color: var(--foreground);
        }
        .fe-header {
          display: grid;
          gap: var(--boxel-sp-4xs);
        }
        .fe-eyebrow {
          font-size: 0.6875rem;
          font-weight: 600;
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: var(--primary-ink);
        }
        .fe-title {
          margin: 0;
          font-size: 1.5rem;
          font-weight: 700;
          line-height: 1.15;
        }
        .fe-desc {
          margin: 0;
          font-size: 0.875rem;
          line-height: 1.5;
          color: var(--primary-ink);
        }
        .fe-panel {
          display: grid;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp);
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius);
          background-color: var(--card);
          color: var(--card-foreground);
        }
        .fe-panel--code {
          background-color: var(--card);
          color: var(--card-foreground);
        }
        .fe-panel-head {
          display: flex;
          align-items: baseline;
          justify-content: space-between;
          gap: var(--boxel-sp-xs);
        }
        .fe-panel-label {
          font-size: 0.75rem;
          font-weight: 600;
          letter-spacing: 0.04em;
          text-transform: uppercase;
          color: var(--subtle-foreground);
        }
        .fe-panel-hint {
          font-size: 0.75rem;
          color: var(--subtle-foreground);
        }
        .fe-api-intro {
          margin: 0;
          font-size: 0.75rem;
          color: var(--primary-ink);
        }
        .fe-api {
          display: grid;
          gap: 1px;
          background-color: var(--inset);
          border: 1px solid var(--border);
          border-radius: 0.375rem;
          overflow: hidden;
        }
        .fe-api-row {
          display: grid;
          grid-template-columns: 1fr 2fr;
          gap: var(--boxel-sp-xs);
          padding: 0.5rem 0.625rem;
          background-color: var(--card);
          color: var(--card-foreground);
          font-size: 0.75rem;
          line-height: 1.4;
        }
        .fe-api-row--head {
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.03em;
          font-size: 0.6875rem;
          color: var(--subtle-foreground);
          background-color: var(--card);
        }
        .fe-api-name {
          font-family: var(--boxel-monospace-font-family);
          color: var(--primary-ink);
          word-break: break-word;
        }
        .fe-api-type {
          color: var(--primary-ink);
        }
        @media (max-width: 500px) {
          .fe-api-row {
            grid-template-columns: 1fr;
            gap: 0.125rem;
          }
          .fe-api-row--head {
            display: none;
          }
        }
      </style>
    </template>
  };
}
