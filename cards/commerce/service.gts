import {
  CardDef,
  Component,
  contains,
  field,
  StringField,
} from '@cardstack/base/card-api';
import WrenchIcon from '@cardstack/boxel-icons/wrench';
import { IsoFrame } from '../shared/compact-sheet';
import { RichFittedCard } from '../shared/rich-fitted-card';

// Service — a billable, non-recurring unit (implementation, support hours,
// onboarding). Kept separate from Plan per the domain-neutral rule: Plan is
// the recurring tier, Service is one-time/ad-hoc. Same Price-lookup pattern
// as Plan — no stored back-link, a Price links to the Service it prices.

export class Service extends CardDef {
  static displayName = 'Service';
  static icon = WrenchIcon;

  @field name = contains(StringField);
  @field description = contains(StringField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Service) {
      return this.name?.trim()?.length
        ? this.name
        : `Untitled ${this.constructor.displayName}`;
    },
  });

  static atom = class Atom extends Component<typeof Service> {
    <template>
      <span class='service-atom'>
        <WrenchIcon class='sa-icon' />
        <span class='sa-name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .service-atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          color: var(--foreground);
        }
        .sa-icon {
          width: 0.875rem;
          height: 0.875rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .sa-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Service> {
    <template>
      <div class='service-row'>
        <WrenchIcon class='icon' />
        <div class='info'>
          <span class='name'>{{@model.cardTitle}}</span>
          {{#if @model.description}}
            <span class='meta'>{{@model.description}}</span>
          {{/if}}
        </div>
      </div>
      <style scoped>
        .service-row {
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

  static fitted = class Fitted extends Component<typeof Service> {
    <template>
      <RichFittedCard>
        <:avatar><WrenchIcon class='mark' aria-hidden='true' /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{@model.description}}</:subtitle>
      </RichFittedCard>
      <style scoped>
        .mark {
          inline-size: var(--pretui-avatar-size);
          block-size: var(--pretui-avatar-size);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Service> {
    <template>
      <IsoFrame>
        <article class='service-page'>
          <header class='sh'>
            <WrenchIcon class='avatar-icon' />
            <div class='sh-id'>
              <p class='doc-kind'>Service</p>
              <h1>{{@model.cardTitle}}</h1>
            </div>
          </header>
          {{#if @model.description}}
            <p class='desc'>{{@model.description}}</p>
          {{/if}}
        </article>
      </IsoFrame>
      <style scoped>
        .service-page {
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
        .sh {
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
      </style>
    </template>
  };
}
