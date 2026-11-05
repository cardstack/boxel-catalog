// Pretui — StatusChip usage page.
import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { FreestyleUsage } from './freestyle-usage';
import { StatusChip } from './status-chip';

class StatusChipUsage extends GlimmerComponent {
  @tracked value = 'in progress';
  setValue = (v: string) => (this.value = v);
  <template>
    <FreestyleUsage
      @name='StatusChip'
      @description='A Chip whose hue is derived by hashing the value — same value, same color, every card, no configuration. Type any status below and watch it keep a stable hue.'
    >
      <:example>
        <StatusChip @value={{this.value}} />
        <StatusChip @value='overdue' />
        <StatusChip @value='review' />
        <StatusChip @value='active' />
      </:example>
      <:api as |Args|>
        <Args.String
          @name='value'
          @value={{this.value}}
          @required={{true}}
          @description='The status text; its hash picks one of the five chart hues deterministically.'
          @onInput={{this.setValue}}
        />
        <Args.String
          @name='appearance'
          @defaultValue='outlined'
          @description="Passed to Chip: 'outlined' or 'soft' (hue-tinted fill, no ring)."
        />
        <Args.String
          @name='shape'
          @defaultValue='rounded'
          @description="Passed to Chip: 'rounded' or 'pill'."
        />
        <Args.Bool
          @name='dot'
          @defaultValue={{true}}
          @description='Passed to Chip: false drops the dot.'
        />
      </:api>
    </FreestyleUsage>
  </template>
}

export const DEMOS_STATUS_CHIP: Record<string, unknown> = {
  StatusChip: StatusChipUsage,
};
