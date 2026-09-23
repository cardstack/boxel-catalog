import {
  FieldDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import DateTimeField from '@cardstack/base/datetime';
import UrlField from '@cardstack/base/url';
import enumField from '@cardstack/base/enum';
import ExternalLinkIcon from '@cardstack/boxel-icons/external-link';
import PlugIcon from '@cardstack/boxel-icons/plug';

export const INTEGRATION_KINDS = [
  'ticketing',
  'crm',
  'chat',
  'repo',
  'other',
] as const;

export const IntegrationKindField = enumField(StringField, {
  displayName: 'Integration Kind',
  options: INTEGRATION_KINDS as unknown as string[],
});

/**
 * A named external system — "Zendesk", "Jira" — so a reference outlives the
 * browser tab that pasted it. Lives on the desk's App Configuration; an
 * External Reference embeds a copy of the parts it needs for display.
 */
export class IntegrationReferenceField extends FieldDef {
  static displayName = 'Integration Reference';
  static icon = PlugIcon;

  @field name = contains(StringField);
  @field kind = contains(IntegrationKindField);
  @field baseUrl = contains(UrlField, {
    description:
      'Root URL of the external system. NOTE: UrlField drops query strings — store the bare origin.',
  });
  @field idPattern = contains(StringField, {
    description: 'Display hint for ids, e.g. "#88123" or "OPS-441".',
  });

  @field title = contains(StringField, {
    computeVia: function (this: IntegrationReferenceField) {
      return this.name ?? 'Integration';
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='integration'>
        <span class='integration-name'>{{if @model.name @model.name '—'}}</span>
        {{#if @model.kind}}<span
            class='integration-kind'
          >{{@model.kind}}</span>{{/if}}
      </span>
      <style scoped>
        .integration {
          display: inline-flex;
          align-items: baseline;
          gap: var(--boxel-sp-4xs);
          font-size: var(--boxel-font-size-sm);
        }
        .integration-name {
          font-weight: 500;
        }
        .integration-kind {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='integration-atom'>{{if @model.name @model.name '—'}}</span>
      <style scoped>
        .integration-atom {
          font-size: var(--boxel-font-size-xs);
        }
      </style>
    </template>
  };
}

/**
 * This record in someone else's system: "Zendesk #88123 (open)".
 *
 * `state` is stored VERBATIM from the other system, never mapped onto local
 * enums — the other system's vocabulary is its own, and mapping is where sync
 * lies begin. `lastSeenAt` says how fresh the fact is.
 */
export class ExternalReferenceField extends FieldDef {
  static displayName = 'External Reference';
  static icon = ExternalLinkIcon;

  @field system = contains(IntegrationReferenceField);
  @field externalId = contains(StringField, {
    description: 'The id as the external system writes it, e.g. "#88123".',
  });
  @field url = contains(UrlField);
  @field lastSeenAt = contains(DateTimeField);
  @field state = contains(StringField, {
    description: "The external system's own status word, verbatim.",
  });

  @field title = contains(StringField, {
    computeVia: function (this: ExternalReferenceField) {
      let sys = this.system?.name;
      if (!sys && !this.externalId) return 'External reference';
      return [sys, this.externalId].filter(Boolean).join(' ');
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='xref'>
        <span class='xref-sys'>{{if
            @model.system.name
            @model.system.name
            '—'
          }}</span>
        <code class='xref-id'>{{if
            @model.externalId
            @model.externalId
            '—'
          }}</code>
        {{#if @model.state}}<span
            class='xref-state'
          >{{@model.state}}</span>{{/if}}
      </span>
      <style scoped>
        .xref {
          display: inline-flex;
          align-items: baseline;
          gap: var(--boxel-sp-4xs);
          border: 1px solid var(--border, var(--boxel-border-color));
          border-radius: var(--boxel-border-radius-sm);
          padding: 0.125rem 0.5rem;
          font-size: var(--boxel-font-size-xs);
        }
        .xref-sys {
          color: var(--muted-foreground, var(--boxel-450));
        }
        .xref-id {
          font-family: var(--font-mono, var(--boxel-monospace-font-family));
          font-weight: 500;
        }
        .xref-state {
          color: var(--muted-foreground, var(--boxel-450));
          font-style: italic;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <code class='xref-atom'>{{@model.title}}</code>
      <style scoped>
        .xref-atom {
          font-family: var(--font-mono, var(--boxel-monospace-font-family));
          font-size: var(--boxel-font-size-xs);
        }
      </style>
    </template>
  };
}

export default ExternalReferenceField;
