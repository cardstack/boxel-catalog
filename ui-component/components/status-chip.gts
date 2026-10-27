// Pretui — StatusChip: a Chip whose hue is derived from its status value, stable across cards.
import Component from '@glimmer/component';
import { Chip } from './chip';
import { statusHue } from '../internal/ink';
import type { PretuiToneArg } from '../pretui-primitives';

export interface StatusChipSignature {
  Args: { value: string; hue?: string; tone?: PretuiToneArg };
  Element: HTMLSpanElement;
}

// A chip whose hue derives from the status VALUE — caller override is the exception.
export class StatusChip extends Component<StatusChipSignature> {
  // Only an untoned chip hashes its value into a hue; any passed tone,
  // neutral included, dots itself from the tone, so a neutral "Intake"
  // can't come out green. @hue overrides both.
  get dotHue() {
    return (
      this.args.hue ??
      (this.args.tone === undefined ? statusHue(this.args.value) : undefined)
    );
  }
  <template>
    <Chip
      @label={{@value}}
      @hue={{this.dotHue}}
      @tone={{@tone}}
      data-test-pretui-status-chip
      ...attributes
    />
  </template>
}
