import {
  CardDef,
  Component,
  contains,
  field,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import CodeSnippet from '../../../components/code-snippet';
import LeafletMapConfigField from '../leaflet-map-config-field';

const usageCode = `@field mapConfig = contains(LeafletMapConfigField);`;

export class LeafletMapConfigExample extends CardDef {
  static displayName = 'Leaflet Map Config Example';

  @field mapConfig = contains(LeafletMapConfigField);
  @field title = contains(StringField);
  @field description = contains(StringField);

  static isolated = class Isolated extends Component<typeof this> {
    apiRows = [
      {
        name: 'tileserverUrl',
        type: 'string',
        default: '—',
        desc: 'Tile server URL template for the map.',
      },
    ];

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
            <span class='fe-panel-hint'>Edit the value</span>
          </div>
          <div class='fe-panel-body'>
            <@fields.mapConfig @format='edit' />
          </div>
        </section>

        <section class='fe-panel'>
          <div class='fe-panel-head'>
            <span class='fe-panel-label'>Preview</span>
            <span class='fe-panel-hint'>Read-only display</span>
          </div>
          <div class='fe-panel-body'>
            <@fields.mapConfig />
          </div>
        </section>

        <section class='fe-panel'>
          <div class='fe-panel-head'>
            <span class='fe-panel-label'>Fields</span>
          </div>
          <p class='fe-api-intro'>Contained fields on this FieldDef.</p>
          <div class='fe-api'>
            <div class='fe-api-row fe-api-row--head'>
              <span>Name</span>
              <span>Type</span>
              <span>Default</span>
              <span>Description</span>
            </div>
            {{#each this.apiRows as |row|}}
              <div class='fe-api-row'>
                <code class='fe-api-name'>{{row.name}}</code>
                <span class='fe-api-type'>{{row.type}}</span>
                <span class='fe-api-default'>{{row.default}}</span>
                <span class='fe-api-desc'>{{row.desc}}</span>
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
        .fe-api-intro {
          margin: 0;
          font-size: 0.75rem;
          color: var(--boxel-500, #64748b);
        }
        .fe-api {
          display: grid;
          gap: 1px;
          background: var(--boxel-200, #e5e7eb);
          border: 1px solid var(--boxel-200, #e5e7eb);
          border-radius: 0.375rem;
          overflow: hidden;
        }
        .fe-api-row {
          display: grid;
          grid-template-columns: 1.2fr 1.4fr 0.8fr 2fr;
          gap: var(--boxel-sp-xs, 0.5rem);
          padding: 0.5rem 0.625rem;
          background: var(--boxel-light, #fff);
          font-size: 0.75rem;
          line-height: 1.4;
        }
        .fe-api-row--head {
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.03em;
          font-size: 0.6875rem;
          color: var(--boxel-400, #94a3b8);
          background: var(--boxel-100, #f8fafc);
        }
        .fe-api-name {
          font-family: var(
            --boxel-monospace-font-family,
            ui-monospace,
            monospace
          );
          color: var(--boxel-purple, #6b46c1);
          word-break: break-word;
        }
        .fe-api-type {
          font-family: var(
            --boxel-monospace-font-family,
            ui-monospace,
            monospace
          );
          color: var(--boxel-500, #64748b);
          word-break: break-word;
        }
        .fe-api-default {
          color: var(--boxel-500, #64748b);
        }
        .fe-api-desc {
          color: var(--boxel-dark, #374151);
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
