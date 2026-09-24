import {
  FieldDef,
  Component,
  field,
  contains,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import DateTimeField from '@cardstack/base/datetime';
import UserPenIcon from '@cardstack/boxel-icons/user-pen';

import { Employee } from '@cardstack/catalog/cards/hr/employee';

/**
 * Who produced an artefact and where it came from.
 *
 * Deliberately separate from Trust Metadata: attribution is provenance (a
 * person and a source), trust is how far to rely on it. The same screenshot
 * can be attributed to a named analyst and still be self-asserted — collapsing
 * the two would make "we know who took this" read as "we believe it".
 *
 * `source` is free text on purpose. It names a system ("exported from the
 * IdP"), a person, or a place ("photographed on site"), and constraining it to
 * an enum would push every consumer into an `other` bucket by its third audit.
 */
export class AttributionField extends FieldDef {
  static displayName = 'Attribution';
  static icon = UserPenIcon;

  @field author = linksTo(() => Employee);
  @field source = contains(StringField);
  @field capturedAt = contains(DateTimeField);
  /** Reuse terms, when the artefact came from outside the organisation. */
  @field license = contains(StringField);

  @field summary = contains(StringField, {
    computeVia: function (this: AttributionField) {
      let parts = [this.source, this.author?.name].filter(Boolean);
      return parts.join(' · ');
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='attribution'>
        {{#if @model.source}}
          <span class='source'>{{@model.source}}</span>
        {{/if}}
        {{#if @model.author}}
          <span class='by'>by <@fields.author @format='atom' /></span>
        {{/if}}
        {{#if @model.capturedAt}}
          <span class='when'><@fields.capturedAt /></span>
        {{/if}}
        {{#if @model.license}}
          <span class='license'>{{@model.license}}</span>
        {{/if}}
      </div>
      <style scoped>
        .attribution {
          display: inline-flex;
          flex-wrap: wrap;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          font-size: 0.8125rem;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .source {
          font-weight: 600;
          color: var(--foreground, var(--boxel-dark));
        }
        .license {
          font-family: var(--font-mono, ui-monospace, monospace);
          font-size: 0.75rem;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>{{@model.summary}}</span>
      <style scoped>
        .atom {
          font-size: 0.75rem;
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };
}

export default AttributionField;
