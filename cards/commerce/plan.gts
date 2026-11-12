import {
  CardDef,
  Component,
  contains,
  containsMany,
  field,
  StringField,
} from '@cardstack/base/card-api';
import LayersIcon from '@cardstack/boxel-icons/layers';
import { IsoFrame } from '../shared/compact-sheet';

// Plan — a named, recurring tier of the product (e.g. "Pro", "Enterprise").
// Deliberately has no price field of its own: a consumer's price records link
// to the Plan, and a Plan's current prices are a query over them rather than
// a stored back-link every price change would rewrite.

export class Plan extends CardDef {
  static displayName = 'Plan';
  static icon = LayersIcon;

  @field name = contains(StringField);
  @field description = contains(StringField);
  @field features = containsMany(StringField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Plan) {
      return this.name?.trim()?.length
        ? this.name
        : `Untitled ${this.constructor.displayName}`;
    },
  });

  static atom = class Atom extends Component<typeof Plan> {
    <template>
      <span class='plan-atom'>
        <LayersIcon class='pa-icon' />
        <span class='pa-name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .plan-atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          color: var(--foreground);
        }
        .pa-icon {
          width: 0.875rem;
          height: 0.875rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .pa-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Plan> {
    <template>
      <div class='plan-row'>
        <LayersIcon class='icon' />
        <div class='info'>
          <span class='name'>{{@model.cardTitle}}</span>
          {{#if @model.description}}
            <span class='meta'>{{@model.description}}</span>
          {{/if}}
        </div>
      </div>
      <style scoped>
        .plan-row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-sm);
        }
        .icon {
          width: 1.25rem;
          height: 1.25rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .info {
          min-width: 0;
          flex: 1;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-6xs);
        }
        .name {
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .meta {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Plan> {
    <template>
      <div class='fitted'>
        <div class='fmt badge'>
          <LayersIcon class='doc-icon' />
          <span class='name'>{{@model.cardTitle}}</span>
        </div>
        <div class='fmt strip'>
          <LayersIcon class='doc-icon' />
          <div class='info'>
            <span class='name'>{{@model.cardTitle}}</span>
          </div>
        </div>
        <div class='fmt tile'>
          <LayersIcon class='doc-icon' />
          <span class='name'>{{@model.cardTitle}}</span>
          {{#if @model.description}}
            <span class='meta'>{{@model.description}}</span>
          {{/if}}
        </div>
        <div class='fmt card'>
          <div class='col'>
            <div class='row'>
              <LayersIcon class='doc-icon' />
              <span class='name name-lg'>{{@model.cardTitle}}</span>
            </div>
            {{#if @model.description}}
              <span class='meta'>{{@model.description}}</span>
            {{/if}}
            {{#if @model.features.length}}
              <span class='meta'>{{@model.features.length}} features</span>
            {{/if}}
          </div>
        </div>
      </div>
      <style scoped>
        .fitted {
          width: 100%;
          height: 100%;
          color: var(--foreground);
        }
        .fmt {
          display: none;
          width: 100%;
          height: 100%;
          box-sizing: border-box;
          overflow: hidden;
        }
        .doc-icon {
          width: 1.25rem;
          height: 1.25rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .name {
          font-weight: 600;
          font-size: var(--boxel-font-size-xs);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          max-width: 100%;
        }
        .name-lg {
          font-size: var(--boxel-font-size-sm);
        }
        .meta {
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          max-width: 100%;
        }
        .row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          min-width: 0;
        }
        .col,
        .info {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-4xs);
          min-width: 0;
          flex: 1;
        }
        @container fitted-card (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            gap: var(--boxel-sp-2xs);
            padding: var(--boxel-sp-xs);
            text-align: center;
          }
        }
        @container fitted-card (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          }
        }
        @container fitted-card (max-width: 399px) and (min-height: 170px) {
          .tile {
            display: flex;
            flex-direction: column;
            align-items: flex-start;
            justify-content: center;
            gap: var(--boxel-sp-2xs);
            padding: var(--boxel-sp-sm);
          }
        }
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .card {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp);
            padding: var(--boxel-sp-lg);
          }
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Plan> {
    <template>
      <IsoFrame>
        <article class='plan-page'>
          <header class='ph'>
            <LayersIcon class='avatar-icon' />
            <div class='ph-id'>
              <p class='doc-kind'>Plan</p>
              <h1>{{@model.cardTitle}}</h1>
            </div>
          </header>
          {{#if @model.description}}
            <p class='desc'>{{@model.description}}</p>
          {{/if}}
          {{#if @model.features.length}}
            <section class='panel'>
              <h2>Features</h2>
              <ul>
                {{#each @model.features as |f|}}
                  <li>{{f}}</li>
                {{/each}}
              </ul>
            </section>
          {{/if}}
        </article>
      </IsoFrame>
      <style scoped>
        .plan-page {
          background: var(--card);
          color: var(--card-foreground);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          max-width: 40rem;
          margin: 0 auto;
          inline-size: 100%;
          padding: var(--boxel-sp-xl) var(--boxel-sp-lg);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
        }
        .ph {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp);
          border-bottom: 2px solid var(--foreground);
          padding-bottom: var(--boxel-sp-lg);
        }
        .avatar-icon {
          width: 2.5rem;
          height: 2.5rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .doc-kind {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          margin: 0 0 var(--boxel-sp-6xs);
          color: var(--muted-foreground);
        }
        h1 {
          font-size: var(--boxel-font-size-lg);
          line-height: 1.1;
        }
        .desc {
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .panel {
          border: 1px solid var(--border);
          border-radius: 0.75rem;
          padding: var(--boxel-sp) var(--boxel-sp-lg);
          background: var(--card);
        }
        h2 {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          margin: 0 0 var(--boxel-sp-sm);
          color: var(--muted-foreground);
        }
        ul {
          margin: 0;
          padding-inline-start: var(--boxel-sp-lg);
          font-size: var(--boxel-font-size-sm);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-2xs);
        }
      </style>
    </template>
  };
}
