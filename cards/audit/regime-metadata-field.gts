import {
  FieldDef,
  Component,
  field,
  contains,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import UrlField from '@cardstack/base/url';
import ScaleIcon from '@cardstack/boxel-icons/scale';

import { CertificationAuthority } from './certification-authority';
import { Token } from '@cardstack/pretui/components/token';
import { ID_TOKEN_STYLE } from './audit-ui';

/**
 * Which rule-set, which edition, which clause. A control means nothing
 * without the clause it satisfies, and auditors speak in clause numbers.
 *
 * Domain-neutral on purpose: "ISO 9001:2015 §8.5.1" and a Boxel standard's
 * "§3.2" are the same shape. A regime-level reference leaves `clause` empty.
 */
export class RegimeMetadataField extends FieldDef {
  static displayName = 'Regime Metadata';
  static icon = ScaleIcon;

  @field regime = contains(StringField);
  @field version = contains(StringField);
  @field clause = contains(StringField);
  @field clauseTitle = contains(StringField);
  @field authority = linksTo(() => CertificationAuthority);
  @field url = contains(UrlField);

  @field reference = contains(StringField, {
    computeVia: function (this: RegimeMetadataField) {
      let parts = [this.regime, this.clause].filter(Boolean);
      return parts.join(' ');
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='regime'>
        {{#if @model.reference}}
          <Token style={{ID_TOKEN_STYLE.sm}}>{{@model.reference}}</Token>
        {{/if}}
        {{#if @model.clauseTitle}}
          <span class='title'>{{@model.clauseTitle}}</span>
        {{/if}}
        {{#if @model.authority}}
          <span class='auth'>·
            <@fields.authority @format='atom' /></span>
        {{/if}}
        {{#if @model.url}}
          <a
            class='link'
            href={{@model.url}}
            target='_blank'
            rel='noopener noreferrer'
          >
            clause text</a>
        {{/if}}
      </div>
      <style scoped>
        .regime {
          display: inline-flex;
          flex-wrap: wrap;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          font-size: 0.875rem;
        }
        .title,
        .auth {
          color: var(--muted-foreground);
        }
        .link {
          font-size: 0.75rem;
          color: var(--foreground);
          text-decoration: underline;
          text-underline-offset: 0.125rem;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      {{#if @model.reference}}
        <Token style={{ID_TOKEN_STYLE.xs}}>{{@model.reference}}</Token>
      {{/if}}
    </template>
  };
}

export default RegimeMetadataField;
