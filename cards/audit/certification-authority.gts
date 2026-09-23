import {
  CardDef,
  Component,
  StringField,
  contains,
  field,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import UrlField from '@cardstack/base/url';
import BuildingIcon from '@cardstack/boxel-icons/building';
import ImageSourceField from '@cardstack/catalog/fields/image-source/image-source';
import { FieldContainer } from '@cardstack/boxel-ui/components';

import { SectionedEdit } from '../../components/sectioned-edit';

/**
 * The body whose name stands behind a certificate — the
 * **Certification Authority** block. Domain-neutral: an academy, a safety
 * board, a professional institute. It owns three things a certificate needs
 * and a course does not: the signatory, the seal, and the number sequence.
 *
 * `lastSequence` is the one mutable fact: Issue Certificate increments it,
 * so the authority is the single writer of its own numbering. A realm has no
 * global counter; this is where the counter lives.
 */
export class CertificationAuthority extends CardDef {
  static displayName = 'Certification Authority';
  static icon = BuildingIcon;

  @field name = contains(StringField);
  @field signatoryName = contains(StringField);
  @field signatoryTitle = contains(StringField);
  @field seal = contains(ImageSourceField);
  @field verificationBaseUrl = contains(UrlField, {
    description:
      'Certificate numbers are appended to this to form a verify link.',
  });
  @field numberPrefix = contains(StringField, {
    description: 'Letters printed before the year in every number, e.g. ACAD.',
  });
  @field lastSequence = contains(NumberField, {
    description: 'Maintained by Issue Certificate. Do not edit by hand.',
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: CertificationAuthority) {
      return this.name?.trim() || 'Unnamed authority';
    },
  });
  @field issuedCount = contains(NumberField, {
    computeVia: function (this: CertificationAuthority) {
      return this.lastSequence ?? 0;
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <article class='authority'>
        <header class='hero'>
          {{#if @model.seal.resolvedUrl}}
            <img class='seal' src={{@model.seal.resolvedUrl}} alt='' />
          {{else}}
            <span class='seal seal-empty' aria-hidden='true'>{{initial
                @model.name
              }}</span>
          {{/if}}
          <div class='hero-text'>
            <span class='eyebrow'>Certification authority</span>
            <h1>{{@model.cardTitle}}</h1>
            {{#if @model.signatoryName}}
              <p class='sig'>Signed by
                <b>{{@model.signatoryName}}</b>{{#if @model.signatoryTitle}},
                  {{@model.signatoryTitle}}{{/if}}</p>
            {{/if}}
          </div>
          <dl class='facts'>
            <div><dt>Numbering</dt><dd class='mono'>{{if
                  @model.numberPrefix
                  @model.numberPrefix
                  'CERT'
                }}-YYYY-000000</dd></div>
            <div><dt>Issued</dt><dd>{{@model.issuedCount}}</dd></div>
          </dl>
        </header>
        <section class='verify'>
          <h2>Verification</h2>
          {{#if @model.verificationBaseUrl}}
            <p>Every certificate links to
              <span
                class='mono'
              >{{@model.verificationBaseUrl}}&lt;number&gt;</span>.</p>
          {{else}}
            <p class='empty'>No verification URL. Certificates will print the
              number without a link.</p>
          {{/if}}
        </section>
      </article>
      <style scoped>
        .authority {
          max-width: 52rem;
          margin: 0 auto;
          container-type: inline-size;
          padding: var(--boxel-sp-xl) var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp-lg);
          color: var(--foreground, var(--boxel-dark));
          background: var(--background, var(--boxel-light));
        }
        .hero {
          display: grid;
          grid-template-columns: auto 1fr auto;
          gap: var(--boxel-sp);
          align-items: center;
        }
        .seal {
          width: 5rem;
          height: 5rem;
          border-radius: 50%;
          object-fit: cover;
          box-shadow:
            0 0 0 3px var(--card, var(--boxel-light)),
            0 0 0 4px var(--primary, var(--boxel-highlight));
        }
        .seal-empty {
          display: grid;
          place-items: center;
          background: color-mix(
            in oklab,
            var(--primary, var(--boxel-highlight)) 14%,
            var(--card, var(--boxel-light))
          );
          font: 700 1.75rem var(--font-heading, var(--boxel-font-family));
        }
        .eyebrow {
          font-size: var(--boxel-font-size-xs);
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: var(--muted-foreground, var(--boxel-450));
        }
        h1 {
          margin: var(--boxel-sp-4xs) 0 0;
          font: 700 var(--boxel-font-size-xl) / 1.15
            var(--font-heading, var(--boxel-font-family));
        }
        .sig {
          margin: var(--boxel-sp-xs) 0 0;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .facts {
          margin: 0;
          display: grid;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-sm) var(--boxel-sp);
          border: 1px solid var(--border, var(--boxel-200));
          border-radius: var(--radius, var(--boxel-border-radius));
          background: var(--card, var(--boxel-light));
        }
        dt {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
        dd {
          margin: 0;
          font-weight: 600;
        }
        .mono {
          font-family: var(--font-mono, ui-monospace, monospace);
          letter-spacing: 0.03em;
        }
        h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .empty {
          color: var(--muted-foreground, var(--boxel-450));
          font-style: italic;
        }
        @container (width <= 600px) {
          .hero {
            grid-template-columns: auto 1fr;
          }
          .facts {
            grid-column: 1 / -1;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='row'>
        {{#if @model.seal.resolvedUrl}}
          <img class='seal' src={{@model.seal.resolvedUrl}} alt='' />
        {{else}}
          <span class='seal seal-empty'>{{initial @model.name}}</span>
        {{/if}}
        <div class='text'>
          <span class='title'>{{@model.cardTitle}}</span>
          <span class='sub'>{{if
              @model.signatoryName
              @model.signatoryName
              'No signatory'
            }}</span>
        </div>
        <span class='count'>{{@model.issuedCount}} issued</span>
      </div>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: auto 1fr auto;
          gap: var(--boxel-sp-xs);
          align-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .seal {
          width: 2.25rem;
          height: 2.25rem;
          border-radius: 50%;
          object-fit: cover;
        }
        .seal-empty {
          display: grid;
          place-items: center;
          background: color-mix(
            in oklab,
            var(--primary, var(--boxel-highlight)) 14%,
            var(--card, var(--boxel-light))
          );
          font-weight: 700;
        }
        .text {
          display: grid;
          min-width: 0;
        }
        .title {
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .sub,
        .count {
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .count {
          white-space: nowrap;
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>{{@model.cardTitle}}</span>
      <style scoped>
        .atom {
          font-size: var(--boxel-font-size-sm);
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof this> {
    sections = [
      { id: 'identity', label: 'Identity' },
      { id: 'signatory', label: 'Signatory' },
      { id: 'seal', label: 'Seal' },
      { id: 'numbering', label: 'Numbering' },
    ];
    <template>
      <SectionedEdit
        @sections={{this.sections}}
        @ariaLabel='Authority sections'
        as |e|
      >
        <e.Section @id='identity' @title='Identity' @cols={{1}}>
          <FieldContainer @label='Name' @vertical={{true}}><@fields.name
            /></FieldContainer>
        </e.Section>
        <e.Section
          @id='signatory'
          @title='Signatory'
          @hint='printed on every certificate'
          @cols={{2}}
        >
          <FieldContainer
            @label='Name'
            @vertical={{true}}
          ><@fields.signatoryName /></FieldContainer>
          <FieldContainer
            @label='Title'
            @vertical={{true}}
          ><@fields.signatoryTitle /></FieldContainer>
        </e.Section>
        <e.Section @id='seal' @title='Seal' @cols={{1}}>
          <FieldContainer @label='Seal image' @vertical={{true}}><@fields.seal
            /></FieldContainer>
        </e.Section>
        <e.Section
          @id='numbering'
          @title='Numbering'
          @hint='last sequence is maintained by Issue Certificate'
          @cols={{3}}
        >
          <FieldContainer
            @label='Prefix'
            @vertical={{true}}
          ><@fields.numberPrefix /></FieldContainer>
          <FieldContainer
            @label='Last sequence'
            @vertical={{true}}
          ><@fields.lastSequence /></FieldContainer>
          <FieldContainer
            @label='Verification base URL'
            @vertical={{true}}
          ><@fields.verificationBaseUrl /></FieldContainer>
        </e.Section>
      </SectionedEdit>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <article class='fit'>
        <div class='fit-top'>
          {{#if @model.seal.resolvedUrl}}
            <img class='seal' src={{@model.seal.resolvedUrl}} alt='' />
          {{else}}
            <span class='seal seal-empty'>{{initial @model.name}}</span>
          {{/if}}
          <div class='fit-head'>
            <h3 class='fit-name'>{{@model.cardTitle}}</h3>
            <span class='fit-eb'>{{@model.issuedCount}}
              certificates issued</span>
          </div>
        </div>
        <dl class='fit-add'>
          {{#if @model.signatoryName}}<div><dt>Signatory</dt><dd
              >{{@model.signatoryName}}</dd></div>{{/if}}
          <div><dt>Prefix</dt><dd class='mono'>{{if
                @model.numberPrefix
                @model.numberPrefix
                'CERT'
              }}</dd></div>
        </dl>
      </article>
      <style scoped>
        .fit {
          height: 100%;
          padding: var(--boxel-sp-xs);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
          overflow: hidden;
        }
        .fit-top {
          display: flex;
          gap: var(--boxel-sp-xs);
          align-items: flex-start;
          min-width: 0;
        }
        .seal {
          flex: none;
          width: 2rem;
          height: 2rem;
          border-radius: 50%;
          object-fit: cover;
        }
        .seal-empty {
          display: grid;
          place-items: center;
          background: color-mix(
            in oklab,
            var(--primary, var(--boxel-highlight)) 14%,
            var(--card, var(--boxel-light))
          );
          font-weight: 700;
        }
        .fit-head {
          min-width: 0;
        }
        .fit-name {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          font-weight: 700;
          line-height: 1.2;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .fit-eb {
          font-size: 11px;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .fit-add {
          display: none;
          margin: 0;
          font-size: var(--boxel-font-size-xs);
        }
        .fit-add div {
          display: flex;
          justify-content: space-between;
          gap: var(--boxel-sp-xs);
          padding: 2px 0;
          border-top: 1px solid var(--border, var(--boxel-200));
        }
        dt {
          color: var(--muted-foreground, var(--boxel-450));
        }
        dd {
          margin: 0;
          font-weight: 600;
        }
        .mono {
          font-family: var(--font-mono, ui-monospace, monospace);
        }
        @container fitted-card (height <= 80px) {
          .fit-top {
            align-items: center;
          }
          .fit-name {
            -webkit-line-clamp: 1;
          }
        }
        @container fitted-card (width <= 150px) {
          .fit-eb {
            display: none;
          }
        }
        @container fitted-card (width <= 120px) {
          .fit-top {
            flex-direction: column;
            align-items: flex-start;
          }
          .fit-eb {
            display: none;
          }
        }
        @container fitted-card (min-width: 250px) and (min-height: 120px) {
          .fit-add {
            display: block;
            margin-top: auto;
          }
        }
        @container fitted-card (min-width: 150px) and (min-height: 190px) {
          .fit-add {
            display: block;
            margin-top: auto;
          }
        }
      </style>
    </template>
  };
}

function initial(name?: string | null): string {
  return (name?.trim()?.[0] ?? '?').toUpperCase();
}

export default CertificationAuthority;
