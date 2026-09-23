import {
  FieldDef,
  Component,
  field,
  contains,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import DateTimeField from '@cardstack/base/datetime';
import FingerprintIcon from '@cardstack/boxel-icons/fingerprint';

import { Employee } from '@cardstack/catalog/cards/hr/employee';

/**
 * Who touched a record, when, and against which version of the rules.
 *
 * `sourceVersion` is the part that is easy to leave out and expensive to
 * miss: a result recorded in March was judged against March's rule, and a
 * rule edited in June does not retroactively change what the auditor saw.
 * Without it a re-read of an old report silently reinterprets it.
 *
 * `changeCount` staying at zero is itself the claim worth making on an
 * append-only record — it says nothing has been rewritten since.
 */
export class AuditMetadataField extends FieldDef {
  static displayName = 'Audit Metadata';
  static icon = FingerprintIcon;

  @field createdBy = linksTo(() => Employee);
  @field createdAt = contains(DateTimeField);
  @field lastChangedBy = linksTo(() => Employee);
  @field lastChangedAt = contains(DateTimeField);
  @field changeCount = contains(NumberField);
  /** Which version of the rule or regime produced this. */
  @field sourceVersion = contains(StringField);

  @field summary = contains(StringField, {
    computeVia: function (this: AuditMetadataField) {
      let when = this.createdAt
        ? this.createdAt.toISOString().slice(0, 10)
        : '';
      let changed =
        (this.changeCount ?? 0) > 0 ? ` · ${this.changeCount} change(s)` : '';
      return `${when}${changed}`.trim();
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='meta'>
        {{#if @model.createdAt}}
          <span>recorded <@fields.createdAt /></span>
        {{/if}}
        {{#if @model.createdBy}}
          <span>by <@fields.createdBy @format='atom' /></span>
        {{/if}}
        {{#if @model.sourceVersion}}
          <span class='mono'>rules {{@model.sourceVersion}}</span>
        {{/if}}
        {{#if @model.changeCount}}
          <span class='changed'>{{@model.changeCount}} change(s) since</span>
        {{else}}
          <span>unchanged since</span>
        {{/if}}
      </div>
      <style scoped>
        .meta {
          display: inline-flex;
          flex-wrap: wrap;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          font-size: 0.75rem;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .mono {
          font-family: var(--font-mono, ui-monospace, monospace);
        }
        .changed {
          font-weight: 600;
          color: var(--state-next-fg, var(--foreground, var(--boxel-dark)));
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

export default AuditMetadataField;
