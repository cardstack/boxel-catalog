import { markDefinition } from '@cardstack/base/mark-definition';
import {
  CardDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import { eq } from '@cardstack/boxel-ui/helpers';
import EmailField from '@cardstack/base/email';
import TextAreaField from '@cardstack/base/text-area';
import AddressField from '@cardstack/base/address';
import enumField from '@cardstack/base/enum';

import { StatePill } from '@cardstack/catalog/components/state-pill';
import type { KeyValueItem } from '@cardstack/pretui/components/key-value';
import { Token } from '@cardstack/pretui/components/token';
import { LegalFacts } from './legal-ui';
import { ID_TOKEN_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import { IsoFrame } from '../shared/compact-sheet';

export const LEGAL_ENTITY_TYPES = [
  'corporation',
  'llc',
  'gmbh',
  'ltd',
  'partnership',
  'sole-proprietorship',
  'nonprofit',
];

export const LEGAL_ENTITY_TYPE_LABELS: Record<string, string> = {
  corporation: 'Corporation',
  llc: 'LLC',
  gmbh: 'GmbH',
  ltd: 'Ltd',
  partnership: 'Partnership',
  'sole-proprietorship': 'Sole Proprietorship',
  nonprofit: 'Nonprofit',
};

export const LegalEntityTypeField = markDefinition(
  enumField(StringField, {
    options: LEGAL_ENTITY_TYPES.map((value) => ({
      value,
      label: LEGAL_ENTITY_TYPE_LABELS[value],
    })),
    displayName: 'Legal Entity Type',
  }),
);

function maskTail(value?: string | null): string {
  let v = (value ?? '').replace(/\s/g, '');
  return v.length ? `••••${v.slice(-4)}` : '';
}

// The formal contracting party: the registered legal person behind a
// commercial relationship. An Account is who you SELL to; a Legal Entity is
// who actually signs — registered name, form, jurisdiction, registration
// number, and the authorized signatory. A Contract reaches its entities
// through its parties and signature blocks, not through a field here.
export class LegalEntity extends CardDef {
  static displayName = 'Legal Entity';

  @field legalName = contains(StringField);
  @field entityType = contains(LegalEntityTypeField);
  @field jurisdiction = contains(StringField, {
    description: 'e.g. Delaware, England & Wales, Singapore',
  });
  @field registrationNumber = contains(StringField);
  @field taxId = contains(StringField);
  @field registeredAddress = contains(AddressField);
  @field signatoryName = contains(StringField);
  @field signatoryTitle = contains(StringField);
  @field signatoryEmail = contains(EmailField);
  @field notes = contains(TextAreaField);

  @field maskedTaxId = contains(StringField, {
    computeVia: function (this: LegalEntity) {
      return maskTail(this.taxId);
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: LegalEntity) {
      return this.legalName?.trim()?.length
        ? this.legalName
        : 'Untitled Entity';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get typeLabel() {
      return LEGAL_ENTITY_TYPE_LABELS[this.args.model?.entityType ?? ''] ?? '—';
    }
    get registrationFacts(): KeyValueItem[] {
      let m = this.args.model;
      return [
        { key: 'Reg. number', value: '' },
        { key: 'Tax ID', value: '' },
        { key: 'Jurisdiction', value: m?.jurisdiction ?? '' },
        {
          key: 'Registered at',
          value: m?.registeredAddress?.fullAddress ?? '',
        },
      ];
    }
    get signatoryFacts(): KeyValueItem[] {
      let m = this.args.model;
      return [
        { key: 'Name', value: m?.signatoryName ?? '' },
        { key: 'Title', value: m?.signatoryTitle ?? '' },
        { key: 'Email', value: '' },
      ];
    }
    <template>
      <IsoFrame>
        <article class='entity'>
          <header class='head'>
            <div>
              <p class='kicker'>Legal Entity</p>
              <h1>{{@model.legalName}}</h1>
              <p class='sub'>{{this.typeLabel}} · {{@model.jurisdiction}}</p>
            </div>
            <StatePill
              @label={{this.typeLabel}}
              @hue='slate'
              @emphatic={{true}}
            />
          </header>
          <div class='grid'>
            <section class='panel'>
              <h2>Registration</h2>
              <LegalFacts @items={{this.registrationFacts}}>
                <:value as |row|>
                  {{#if (eq row.key 'Reg. number')}}
                    {{#if @model.registrationNumber}}
                      <Token
                        @value={{@model.registrationNumber}}
                        style={{ID_TOKEN_STYLE.sm}}
                      />
                    {{/if}}
                  {{else if (eq row.key 'Tax ID')}}
                    {{#if @model.maskedTaxId}}
                      <Token
                        @value={{@model.maskedTaxId}}
                        style={{ID_TOKEN_STYLE.sm}}
                      />
                    {{/if}}
                  {{else}}
                    {{row.value}}
                  {{/if}}
                </:value>
              </LegalFacts>
            </section>
            <section class='panel'>
              <h2>Authorized Signatory</h2>
              <LegalFacts @items={{this.signatoryFacts}}>
                <:value as |row|>
                  {{#if (eq row.key 'Email')}}
                    {{#if @model.signatoryEmail}}<@fields.signatoryEmail
                      />{{/if}}
                  {{else}}
                    {{row.value}}
                  {{/if}}
                </:value>
              </LegalFacts>
            </section>
            {{#if @model.notes}}
              <section class='panel span'>
                <h2>Notes</h2>
                <p class='notes'>{{@model.notes}}</p>
              </section>
            {{/if}}
          </div>
        </article>
      </IsoFrame>
      <style scoped>
        .entity {
          background: var(--card);
          color: var(--card-foreground);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          container-type: inline-size;
          padding: var(--boxel-sp-lg);
        }
        .head {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          gap: var(--boxel-sp);
          border-bottom: 1px solid var(--border);
          padding-bottom: var(--boxel-sp);
          margin-bottom: var(--boxel-sp);
        }
        .kicker {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: 0.5625rem; /* 9px ladder label: no token */
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        h1 {
          margin: var(--boxel-sp-5xs) 0;
          font-size: var(--boxel-font-size-lg);
        }
        .sub {
          color: var(--muted-foreground);
        }
        .grid {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: var(--boxel-sp);
        }
        .panel {
          border: 1px solid var(--border);
          border-radius: var(--radius);
          padding: var(--boxel-sp);
          background-color: var(--card);
        }
        .panel.span {
          grid-column: 1 / -1;
        }
        h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-family: var(--boxel-eyebrow-font-family);
          font-size: 0.5625rem; /* 9px ladder label: no token */
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .notes {
          white-space: pre-wrap;
          font-size: var(--boxel-font-size-sm);
        }
        @container (max-width: 560px) {
          .grid {
            grid-template-columns: 1fr;
          }
          .head {
            flex-direction: column;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get typeLabel() {
      return LEGAL_ENTITY_TYPE_LABELS[this.args.model?.entityType ?? ''] ?? '—';
    }
    <template>
      <div class='row'>
        <div class='who'>
          <span class='name'>{{@model.legalName}}</span>
          <span class='meta'>{{this.typeLabel}}
            ·
            {{@model.jurisdiction}}</span>
        </div>
        {{#if @model.registrationNumber}}
          <Token
            @value={{@model.registrationNumber}}
            style={{ID_TOKEN_STYLE.xs}}
          />
        {{/if}}
      </div>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: 1fr auto;
          gap: var(--boxel-sp-sm);
          align-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .who {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-6xs);
          min-width: 0;
        }
        .name {
          font-weight: 600;
          font-size: var(--boxel-font-size-sm);
        }
        .meta {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>{{@model.legalName}}</span>
      <style scoped>
        .atom {
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get typeLabel() {
      return LEGAL_ENTITY_TYPE_LABELS[this.args.model?.entityType ?? ''] ?? '—';
    }
    <template>
      <div class='fit'>
        <span class='fit-name'>{{@model.legalName}}</span>
        <span class='fit-sub'>{{this.typeLabel}}
          ·
          {{@model.jurisdiction}}</span>
      </div>
      <style scoped>
        .fit {
          height: 100%;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-5xs);
          padding: var(--boxel-sp-xs);
          overflow: hidden;
        }
        .fit-name {
          font-weight: 600;
          font-size: var(--boxel-font-size-sm);
          line-height: 1.2;
          overflow: hidden;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
        }
        .fit-sub {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        @container fitted-card (height <= 65px) {
          .fit {
            flex-direction: row;
            align-items: center;
            gap: var(--boxel-sp-xs);
          }
          .fit-name {
            -webkit-line-clamp: 1;
          }
        }
      </style>
    </template>
  };
}
