import {
  CardDef,
  Component,
  contains,
  containsMany,
  field,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';

import { SchemaFilePreview } from '../schema-file-preview';
import { SchemaFieldSummaryField } from '../../fields/schema-field-summary/schema-field-summary-field';

/**
 * A sampled order export summarised field by field, so the preview shows a
 * required key, an optional one, an enum and a field no sampled record carried.
 */
export class SchemaFilePreviewExample extends CardDef {
  static displayName = 'Schema File Preview Example';

  @field title = contains(StringField);
  @field rootType = contains(StringField);
  @field fields = containsMany(SchemaFieldSummaryField);

  static isolated = class Isolated extends Component<typeof this> {
    get fields(): SchemaFieldSummaryField[] {
      return this.args.model.fields ?? [];
    }

    <template>
      <div class='wrap'>
        <SchemaFilePreview
          @fields={{this.fields}}
          @title={{@model.title}}
          @rootType={{@model.rootType}}
          @searchable={{true}}
        />
      </div>
      <style scoped>
        .wrap {
          padding: var(--boxel-sp-lg);
        }
      </style>
    </template>
  };
}
