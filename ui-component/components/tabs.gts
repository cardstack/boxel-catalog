// Pretui — Tabs: tablist + yielded panel. The underline is the same
// SlidingHighlight SegmentedControl wears, in its underline cut.
import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { slidingHighlight, SlidingHighlight } from './sliding-highlight';
import { emit, firstDefined } from '../pretui-primitives';
import type { SegmentOption } from './segmented-control';

export interface TabsSignature {
  Args: {
    options?: SegmentOption[];
    /** alias — the canonical flat-collection noun */
    items?: SegmentOption[];
    value?: string;
    defaultValue?: string;
    onValueChange?: (value: string) => void;
    /** alias — the HTML/Mantine/Ant notify name */
    onChange?: (value: string) => void;
  };
  Blocks: { default: [active: string] };
  Element: HTMLDivElement;
}

// The underline is the same shared primitive the SegmentedControl wears, in
// its `underline` cut: one <SlidingHighlight /> travelling along the rail
// instead of an ::after grown on whichever tab happens to be active. The
// modifier goes on the tablist rather than the outer wrapper so the yielded
// panel's own content can never be mistaken for the active tab.
export class Tabs extends Component<TabsSignature> {
  @tracked internal =
    this.args.defaultValue ??
    (this.args.options ?? this.args.items ?? [])[0]?.value;
  get options(): SegmentOption[] {
    return firstDefined(this.args.options, this.args.items) ?? [];
  }
  get value() {
    return this.args.value ?? this.internal;
  }
  pick = (option: SegmentOption) => {
    if (this.args.value === undefined) {
      this.internal = option.value;
    }
    emit([this.args.onValueChange, this.args.onChange], option.value);
  };
  isActive = (option: SegmentOption) => this.value === option.value;
  <template>
    <div data-test-pretui-tabs ...attributes>
      <div class='pretui-tabs' role='tablist' {{slidingHighlight}}>
        <div class='pretui-tabs-rail'></div>
        <SlidingHighlight @variant='underline' @thickness={{2}} @radius={{0}} />
        {{#each this.options as |option|}}
          <button
            type='button'
            role='tab'
            aria-selected={{if (this.isActive option) 'true' 'false'}}
            class='pretui-tab'
            data-state={{if (this.isActive option) 'active'}}
            {{on 'click' (fn this.pick option)}}
          >{{option.label}}</button>
        {{/each}}
      </div>
      {{#if (has-block)}}
        <div role='tabpanel' class='pretui-tabpanel'>{{yield this.value}}</div>
      {{/if}}
    </div>
    <style scoped>
      @layer PretComponent {
        .pretui-tabs {
          position: relative;
          display: flex;
          gap: var(--boxel-sp-lg);
        }
        .pretui-tab {
          position: relative;
          height: var(--boxel-sp-2xl);
          padding: 0 var(--boxel-sp-4xs);
          border: 0;
          background: none;
          font-family: inherit;
          font-size: var(--boxel-ui-label-font-size);
          font-weight: 600;
          letter-spacing: inherit;
          color: var(--muted-foreground);
          cursor: pointer;
          transition: color 150ms var(--pretui-ease-snap, ease);
        }
        .pretui-tab:hover {
          color: var(--foreground);
        }
        .pretui-tab[data-state='active'] {
          color: var(--foreground);
        }
        /* The active 2px accent bar is the shared SlidingHighlight. This 1px
           rail is the baseline it sits on, along the bottom of the tab row. */
        .pretui-tabs-rail {
          position: absolute;
          bottom: 0;
          left: 0;
          right: 0;
          height: 1px;
          background: var(--border);
        }
        .pretui-tabpanel {
          padding-top: var(--boxel-sp-sm);
        }
      }
    </style>
  </template>
}
