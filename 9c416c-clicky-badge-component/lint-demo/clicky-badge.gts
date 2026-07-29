import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';

export interface ClickyBadgeSignature {
  Args: {
    label?: string;
  };
  Element: HTMLButtonElement;
  Blocks: {};
}

export default class ClickyBadge extends GlimmerComponent<ClickyBadgeSignature> {
  @tracked isActive = false;

  toggle = () => {
    this.isActive = !this.isActive;
  };

  <template>
    <button
      type='button'
      class='badge {{if this.isActive "active"}}'
      {{on 'click' this.toggle}}
      ...attributes
    >
      {{if @label @label 'Status'}}:
      {{if this.isActive 'Active' 'Idle'}}
    </button>
    <style scoped>
      .badge {
        display: inline-block;
        padding: var(--boxel-sp-xs) var(--boxel-sp);
        border: none;
        border-radius: var(--boxel-border-radius);
        background: var(--boxel-200);
        font: var(--boxel-font-sm);
        cursor: pointer;
      }
      .badge.active {
        background: var(--boxel-highlight);
      }
    </style>
  </template>
}
