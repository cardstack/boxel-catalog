import {
  FieldDef,
  field,
  contains,
  containsMany,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import TextAreaField from '@cardstack/base/text-area';
import { Component } from '@cardstack/base/card-api';

/**
 * One field, as a schema describes it.
 *
 * ### Which schema — this is the part worth being precise about
 *
 * **Not** a card type's schema. `host/app/tools/get-card-type-schema.ts`
 * already generates JSON Schema *for a CardDef*, for LLM tool calls, and
 * `Spec/host-get-card-type-schema` covers it. That is a different subject with
 * a different consumer.
 *
 * This describes **the shape a data file declares**: one entry in a JSON
 * Schema document, an OpenAPI component, a CSV header with an inferred type.
 * The reader is someone looking at a file in a realm asking "what is in here,
 * and what does each key mean".
 *
 * ### The gap
 *
 * `JsonFileDef` carries `rootType`, `keyCount` and `lineCount` — the whole
 * document at a glance and nothing about the fields inside it. A reader can
 * see a JSON file has 47 keys and still not know one of them.
 *
 * ### `path` is the identity, `name` is the label
 *
 * Dotted, array-aware: `order.items[].sku`. A nested field's name is not
 * unique — three different objects can each have an `id` — so anything that
 * keys, sorts or links to a field must use `path`.
 *
 * `depth` is derived from it rather than stored, so the two cannot disagree.
 */
export class SchemaFieldSummaryField extends FieldDef {
  static displayName = 'Schema Field Summary';

  @field path = contains(StringField, {
    description:
      'Dotted, array-aware path — order.items[].sku. The identity; name is not unique across nesting.',
  });
  @field name = contains(StringField, {
    description: 'Last segment, for display.',
  });
  @field type = contains(StringField, {
    description:
      'As the schema declares it: string, number, integer, boolean, object, array, null.',
  });
  @field format = contains(StringField, {
    description: 'Refinement of type: date-time, email, uri, uuid.',
  });
  @field required = contains(BooleanField);
  // TextArea rather than String: a schema description is prose the author
  // wrote, and is regularly a paragraph. A single-line input silently
  // discourages carrying it through in full.
  @field description = contains(TextAreaField, {
    description: 'The schema author’s own words, carried through unchanged.',
  });

  // An enum is the single most useful thing a schema can tell a reader — it
  // turns "a string" into "one of these five". Stored as strings whatever the
  // declared type, because display is the job here, not validation.
  @field enumValues = containsMany(StringField);

  @field example = contains(StringField, {
    description: 'One sample value, as text.',
  });

  // Presence in the data, when a sampler measured it. Distinct from
  // `required`: a field can be required by the schema and absent in practice,
  // and that disagreement is exactly what a reader wants to see.
  @field occurrenceCount = contains(NumberField);
  @field sampledCount = contains(NumberField);

  @field depth = contains(NumberField, {
    computeVia: function (this: SchemaFieldSummaryField) {
      if (!this.path) {
        return 0;
      }
      return this.path.split('.').length - 1;
    },
  });

  @field isArray = contains(BooleanField, {
    computeVia: function (this: SchemaFieldSummaryField) {
      return this.type === 'array' || Boolean(this.path?.includes('[]'));
    },
  });

  @field hasEnum = contains(BooleanField, {
    computeVia: function (this: SchemaFieldSummaryField) {
      return (this.enumValues ?? []).length > 0;
    },
  });

  // "string · date-time · required", assembled from whatever is present. The
  // one line a dense schema table shows per row.
  @field typeLabel = contains(StringField, {
    computeVia: function (this: SchemaFieldSummaryField) {
      let parts = [this.type, this.format].filter(Boolean) as string[];
      if (this.required) {
        parts.push('required');
      }
      return parts.join(' · ');
    },
  });

  // Undefined rather than 0 when nothing was sampled — "never seen" and
  // "not measured" must not render the same.
  @field fillRate = contains(NumberField, {
    computeVia: function (this: SchemaFieldSummaryField) {
      if (!this.sampledCount) {
        return undefined;
      }
      return Number(
        (((this.occurrenceCount ?? 0) / this.sampledCount) * 100).toFixed(1),
      );
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='f'>
        <span class='path'>{{if @model.path @model.path @model.name}}</span>
        <span class='type'>{{@model.typeLabel}}</span>
        {{! undefined fillRate renders as nothing, not 0% — an unmeasured
          field and a never-present one must not look the same. }}
        {{#if @model.fillRate}}
          <span class='fill'>{{@model.fillRate}}%</span>
        {{/if}}
      </div>
      <style scoped>
        .f {
          display: flex;
          align-items: baseline;
          gap: var(--boxel-sp-xxs);
          color: var(--foreground);
        }
        .path {
          flex: 1;
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          font: var(--boxel-font-sm);
          font-family: var(--font-mono);
        }
        .type,
        .fill {
          flex: none;
          font: var(--boxel-font-xs);
          color: var(--muted-foreground);
        }
        .fill {
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };
}

export default SchemaFieldSummaryField;
