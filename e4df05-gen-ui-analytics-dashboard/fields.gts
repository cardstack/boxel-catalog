import { FieldDef, Component, field, contains } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import OptionPicker from './components/option-picker';
import { BUCKETS, AGGREGATES } from './utils/chart-spec';

// ---------------------------------------------------------------------------
// The compound axis fields a ChartCard is built from. The enum fields are
// string fields whose edit UI is a row of pills; they stay module-private
// because only DimensionField / MeasureField consume them.
// ---------------------------------------------------------------------------

class BucketField extends StringField {
  static displayName = 'Time Bucket';
  static edit = class Edit extends Component<typeof BucketField> {
    <template>
      <OptionPicker
        @label='Time bucket'
        @options={{BUCKETS}}
        @value={{@model}}
        @set={{@set}}
      />
    </template>
  };
}

class AggregateField extends StringField {
  static displayName = 'Aggregate';
  static edit = class Edit extends Component<typeof AggregateField> {
    <template>
      <OptionPicker
        @label='Aggregate'
        @options={{AGGREGATES}}
        @value={{@model}}
        @set={{@set}}
      />
    </template>
  };
}

// the x axis: which field, and how dates bucket
export class DimensionField extends FieldDef {
  static displayName = 'Dimension';
  @field path = contains(StringField);
  @field bucket = contains(BucketField);

  static embedded = class Embedded extends Component<typeof DimensionField> {
    <template>
      <p class='axis'>
        <span class='axis-path'>{{if @model.path @model.path '—'}}</span>
        {{#if @model.bucket}}
          <span class='axis-meta'>by {{@model.bucket}}</span>
        {{/if}}
      </p>
      <style scoped>
        .axis {
          display: flex;
          gap: var(--boxel-sp-xs);
          align-items: baseline;
        }
        .axis-path {
          font-weight: 600;
        }
        .axis-meta {
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}

// the y axis: which numeric field, and how values combine
export class MeasureField extends FieldDef {
  static displayName = 'Measure';
  @field path = contains(StringField);
  @field aggregate = contains(AggregateField);

  static embedded = class Embedded extends Component<typeof MeasureField> {
    <template>
      <p class='axis'>
        <span class='axis-meta'>{{if
            @model.aggregate
            @model.aggregate
            'count'
          }}</span>
        <span class='axis-path'>{{if @model.path @model.path '*'}}</span>
      </p>
      <style scoped>
        .axis {
          display: flex;
          gap: var(--boxel-sp-xs);
          align-items: baseline;
        }
        .axis-path {
          font-weight: 600;
        }
        .axis-meta {
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}
