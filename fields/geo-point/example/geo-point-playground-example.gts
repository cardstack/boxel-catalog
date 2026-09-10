import { CardDef, Component, contains, field } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import CodeSnippet from '../../../components/code-snippet';
import GeoPointField, { type GeoPointConfiguration } from '../geo-point';

const demoConfig: GeoPointConfiguration = {
  variant: 'map-picker',
  options: { showCurrentLocation: true, mapHeight: '260px' },
};

const usageCode = `@field location = contains(GeoPointField);`;
const configCode = `const demoConfig: GeoPointConfiguration = {
  variant: 'map-picker',
  options: { showCurrentLocation: true, mapHeight: '260px' },
};

@field configuredLocation = contains(GeoPointField, {
  configuration: demoConfig,
});`;

export class GeoPointExample extends CardDef {
  static displayName = 'Geo Point Example';

  @field location = contains(GeoPointField);
  @field configuredLocation = contains(GeoPointField, {
    configuration: demoConfig,
  });
  @field title = contains(StringField);
  @field description = contains(StringField);

  static isolated = class Isolated extends Component<typeof this> {
    apiRows = [
      {
        name: 'variant',
        type: 'standard | map-picker',
        default: 'standard',
        desc: 'Plain inputs or an interactive map picker.',
      },
      {
        name: 'showCurrentLocation',
        type: 'boolean',
        default: '—',
        desc: 'Show a locate-me control.',
      },
      {
        name: 'quickLocations',
        type: 'string[]',
        default: '—',
        desc: 'Preset location shortcuts.',
      },
      {
        name: 'tileserverUrl',
        type: 'string',
        default: '—',
        desc: 'Map tile server URL (map-picker).',
      },
      {
        name: 'mapHeight',
        type: 'string',
        default: '—',
        desc: 'Map height CSS value (map-picker).',
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
            <@fields.location @format='edit' />
          </div>
        </section>

        <section class='fe-panel'>
          <div class='fe-panel-head'>
            <span class='fe-panel-label'>Preview</span>
            <span class='fe-panel-hint'>Read-only display</span>
          </div>
          <div class='fe-panel-body'>
            <@fields.location />
          </div>
        </section>

        <section class='fe-panel'>
          <div class='fe-panel-head'>
            <span class='fe-panel-label'>Configured</span>
            <span class='fe-panel-hint'>With @configuration applied</span>
          </div>
          <div class='fe-panel-body'>
            <@fields.configuredLocation @format='edit' />
          </div>
          <CodeSnippet @code={{configCode}} />
        </section>

        <section class='fe-panel'>
          <div class='fe-panel-head'>
            <span class='fe-panel-label'>Configuration options</span>
          </div>
          <p class='fe-api-intro'>Typed by GeoPointConfiguration, exported by
            the field.</p>
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
          grid-template-columns: 1.2fr 1.4fr 0.8fr 2fr;
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
          background-color: var(--inset);
        }
        .fe-api-name {
          font-family: var(--boxel-monospace-font-family);
          color: var(--primary-ink);
          word-break: break-word;
        }
        .fe-api-type {
          font-family: var(--boxel-monospace-font-family);
          color: var(--primary-ink);
          word-break: break-word;
        }
        .fe-api-default {
          color: var(--primary-ink);
        }
        .fe-api-desc {
          color: var(--foreground);
        }
        @media (max-width: 500px) {
          .fe-api-row {
            grid-template-columns: 1fr;
            gap: 0.125rem;
          }
          .fe-api-row--head {
            display: none;
            background-color: var(--inset);
            color: var(--foreground);
          }
        }
      </style>
    </template>
  };
}
