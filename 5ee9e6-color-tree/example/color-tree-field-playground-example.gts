// Playground example for ColorTreeField — shows the field the way a card
// author will meet it: the 3D studio as the edit format, the compact
// embedded/atom read-outs, and the one-line `contains()` to adopt it.
import {
  CardDef,
  Component,
  contains,
  field,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import CodeSnippet from '../../components/code-snippet';
import { ColorTreeField } from '../color-tree-field';

const usageCode = `import { ColorTreeField } from '@cardstack/catalog/5ee9e6-color-tree/color-tree-field';

export class MyCard extends CardDef {
  @field accentColor = contains(ColorTreeField);
}`;

export class ColorTreeFieldExample extends CardDef {
  static displayName = 'Color Tree Field Example';

  @field pick = contains(ColorTreeField);
  @field title = contains(StringField);
  @field description = contains(StringField);

  static isolated = class Isolated extends Component<typeof this> {
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
            <span class='fe-panel-hint'>Open the atlas, hold a spot to pick</span>
          </div>
          <div class='fe-panel-body'>
            <@fields.pick @format='edit' />
          </div>
        </section>

        <section class='fe-panel'>
          <div class='fe-panel-head'>
            <span class='fe-panel-label'>Preview</span>
            <span class='fe-panel-hint'>Embedded and atom formats</span>
          </div>
          <div class='fe-panel-body fe-panel-body--row'>
            <@fields.pick />
            <@fields.pick @format='atom' />
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
          gap: var(--boxel-sp, 1rem);
          max-width: 680px;
          margin-inline: auto;
          padding: var(--boxel-sp-lg, 1.5rem);
          font-family: var(--boxel-font-family, system-ui, sans-serif);
          color: var(--boxel-dark, #111827);
        }
        .fe-header {
          display: grid;
          gap: var(--boxel-sp-4xs, 0.25rem);
        }
        .fe-eyebrow {
          font-size: 0.6875rem;
          font-weight: 600;
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: var(--boxel-purple, #6b46c1);
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
          color: var(--boxel-500, #64748b);
        }
        .fe-panel {
          display: grid;
          gap: var(--boxel-sp-xs, 0.5rem);
          padding: var(--boxel-sp, 1rem);
          border: 1px solid var(--boxel-200, #e5e7eb);
          border-radius: var(--boxel-border-radius, 0.5rem);
          background: var(--boxel-light, #fff);
        }
        .fe-panel--code {
          background: var(--boxel-100, #f8fafc);
        }
        .fe-panel-head {
          display: flex;
          align-items: baseline;
          justify-content: space-between;
          gap: var(--boxel-sp-xs, 0.5rem);
        }
        .fe-panel-label {
          font-size: 0.75rem;
          font-weight: 600;
          letter-spacing: 0.04em;
          text-transform: uppercase;
          color: var(--boxel-400, #94a3b8);
        }
        .fe-panel-hint {
          font-size: 0.75rem;
          color: var(--boxel-400, #94a3b8);
        }
        .fe-panel-body--row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-lg, 1.5rem);
          flex-wrap: wrap;
        }
      </style>
    </template>
  };
}
