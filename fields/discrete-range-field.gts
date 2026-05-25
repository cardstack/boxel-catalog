import {
  FieldDef,
  field,
  contains,
  Component,
} from 'https://cardstack.com/base/card-api';
import NumberField from 'https://cardstack.com/base/number';
import { StepRangeScroller } from '../components/step-range-scroller';

export default class DiscreteRangeField extends FieldDef {
  static displayName = 'Discrete Range';

  @field startValue = contains(NumberField);
  @field endValue = contains(NumberField);
  @field min = contains(NumberField);
  @field max = contains(NumberField);
  @field interval = contains(NumberField);

  static edit = class Edit extends Component<typeof this> {
    <template>
      <div data-test-discrete-range-edit>
        <StepRangeScroller
          @startValue={{@model.startValue}}
          @endValue={{@model.endValue}}
          @min={{@model.min}}
          @max={{@model.max}}
          @interval={{@model.interval}}
          @onChange={{this.updateRange}}
        />
      </div>
    </template>

    updateRange = (values: { startValue: number; endValue: number }) => {
      this.args.model.startValue = values.startValue;
      this.args.model.endValue = values.endValue;
    };
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='discrete-range-display' data-test-discrete-range-embedded>
        <span data-test-discrete-range-value>{{@model.startValue}}
          -
          {{@model.endValue}}</span>
      </div>
      <style scoped>
        .discrete-range-display {
          padding: 0.5rem;
          background: var(--boxel-50);
          border-radius: 0.25rem;
          text-align: center;
          font-weight: 500;
        }
      </style>
    </template>
  };
}
