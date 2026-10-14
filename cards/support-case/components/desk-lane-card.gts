import GlimmerComponent from '@glimmer/component';
import { StatePill, stateColor } from '../../../components/state-pill';

interface Signature {
  Args: {
    /** The record's id line, in mono. */
    label?: string;
    pillLabel?: string;
    /** A state-pill hue; it also colours the card's accent edge. */
    hue?: string;
  };
  Blocks: { lead: []; default: []; foot: []; action: [] };
  Element: HTMLDivElement;
}

/** A card face inside the shared Board's card chrome. The Board owns hover,
    drag and selection; this only lays out the facts. */
export class DeskLaneCard extends GlimmerComponent<Signature> {
  get pillHue(): any {
    return this.args.hue ?? 'slate';
  }
  get style() {
    return `--lcard-accent: ${stateColor((this.args.hue as any) ?? 'slate').ring};`;
  }

  <template>
    <div class='lcard' style={{this.style}} ...attributes>
      <span class='lcard-top'>
        {{yield to='lead'}}
        <span class='lcard-id'>{{@label}}</span>
        {{#if @pillLabel}}<StatePill
            @label={{@pillLabel}}
            @hue={{this.pillHue}}
          />{{/if}}
      </span>
      <span class='lcard-title'>{{yield}}</span>
      <span class='lcard-foot'>{{yield to='foot'}}</span>
      {{#if (has-block 'action')}}
        <span class='lcard-action'>{{yield to='action'}}</span>
      {{/if}}
    </div>
    <style scoped>
      .lcard {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-4xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm) var(--boxel-sp-xs)
          calc(var(--boxel-sp-sm) + 0.125rem);
        min-width: 0;
        height: 100%;
        border-left: 0.1875rem solid var(--lcard-accent);
        border-radius: 0 var(--radius) var(--radius) 0;
      }
      .lcard-top {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-4xs);
        min-width: 0;
      }
      .lcard-id {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
        flex: 1;
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .lcard-title {
        font-size: var(--boxel-font-size);
        line-height: 1.35;
        font-weight: 500;
        flex: 1;
        overflow: hidden;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
      }
      .lcard-foot {
        display: flex;
        justify-content: space-between;
        gap: var(--boxel-sp-4xs);
        margin-top: auto;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      .lcard-action {
        align-self: flex-end;
      }
    </style>
  </template>
}
