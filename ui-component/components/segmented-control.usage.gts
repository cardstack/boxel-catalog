import { array } from '@ember/helper';
// Pretui — SegmentedControl usage page.
import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { FreestyleUsage } from './freestyle-usage';
import { SegmentedControl } from './segmented-control';

const VIEW_OPTIONS = [
  { value: 'card', label: 'Card' },
  { value: 'strip', label: 'Strip' },
  { value: 'grid', label: 'Grid' },
];
const VIEW_VALUES = VIEW_OPTIONS.map((o) => o.value);
// ── SegmentedControl ← view-selector/usage.gts ───────────────────────────
// Dropped knobs: @disabled (not in SegmentedControlSignature), icon items
// (options are {value, label} text — ViewSelector's icon components have no
// slot in wave-0).
export class SegmentedControlUsage extends Component {
  viewOptions = VIEW_OPTIONS;
  viewValues = VIEW_VALUES;
  @tracked value = 'card';
  setValue = (v: string) => (this.value = v);
  get usage() {
    return `<SegmentedControl @options={{this.views}} @value='${this.value}' @onValueChange={{this.setValue}} />`;
  }
  <template>
    <FreestyleUsage
      @name='SegmentedControl'
      @description="A compact segmented control for switching between a small set of views or modes — text-labeled segments on an inset rail, superseding boxel-ui's ViewSelector. The active card face is not the segment's own background: it composes motion-core's SlidingHighlight (pill cut), so one indicator travels between segments and the reader sees where the selection came from. Under reduced motion it lands on the new segment instantly."
      @source={{this.usage}}
    >
      <:example>
        <SegmentedControl
          @options={{this.viewOptions}}
          @value={{this.value}}
          @onValueChange={{this.setValue}}
        />
      </:example>
      <:api as |Args|>
        <Args.Object
          @name='options'
          @required={{true}}
          @description="Items with a value and a label to render on the selector — boxel-ui ViewSelector's @items took icon components."
          @value={{this.viewOptions}}
        />
        <Args.String
          @name='value'
          @required={{true}}
          @defaultValue='card'
          @value={{this.value}}
          @options={{this.viewValues}}
          @description="Id of the currently selected item — boxel-ui ViewSelector's @selectedId."
          @onInput={{this.setValue}}
        />
        <Args.String
          @name='size'
          @options={{array 'xs' 's' 'm' 'l' 'xl'}}
          @description='Opt-in control scale shared with Button and SearchInput (xs 24 · s 32 · m 40 · l 48 · xl 56 high) with that scale’s text, so a toolbar row can match one height. Unset keeps the compact default.'
        />
        <Args.String
          @name='appearance'
          @options={{array 'raised' 'tinted'}}
          @defaultValue='raised'
          @description="'raised' is an inset rail with a card-face pill on the active segment. 'tinted' is a white rail with a soft-tinted pill and the active label in --primary. The active weight changes in both, so selection is never colour alone."
        />
        <Args.Action
          @name='onValueChange'
          @required={{true}}
          @description='Receives the selected id as a string'
        />
      </:api>
    </FreestyleUsage>
  </template>
}

export const DEMOS_SEGMENTED_CONTROL: Record<string, unknown> = {
  SegmentedControl: SegmentedControlUsage,
};
