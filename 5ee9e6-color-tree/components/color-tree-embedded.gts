// A compact display-only summary of the card: the picked swatch, hex, and
// Munsell notation. Interaction lives entirely in the isolated format.
import { Component } from 'https://cardstack.com/base/card-api';
import { swatchStyle } from '../utils/munsell';
import type { ColorTree } from '../color-tree';

export class ColorTreeEmbedded extends Component<typeof ColorTree> {
  get hasLinkedTheme() {
    return Boolean((this.args.model as any)?.cardInfo?.theme);
  }

  <template>
    <div class='ct-embedded {{unless this.hasLinkedTheme "ct-default"}}'>
      <span class='swatch' style={{swatchStyle @model.selectedColor}}></span>
      <div class='meta'>
        <div class='name'>THE COLOR TREE</div>
        {{#if @model.selectedColor}}
          <div class='detail'>{{@model.selectedColor}}
            ·
            {{@model.selectedMunsell}}</div>
        {{else}}
          <div class='detail'>no chip picked yet</div>
        {{/if}}
      </div>
    </div>

    <style scoped>
      .ct-embedded {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-sm, 0.8rem);
        padding: var(--boxel-sp-sm, 0.9rem) var(--boxel-sp, 1rem);
        /* paint with the theme's matched pair — never mix scopes so the
           background and its text always come from the same author */
        background: var(--card, #050a12);
        color: var(--card-foreground, #e8f1f4);
        font-family: var(--font-mono, ui-monospace, 'SF Mono', monospace);
      }
      /* themeless default: pin the night-sky brand as a matched pair */
      .ct-default {
        --card: var(--ct-surface, #050a12);
        --card-foreground: var(--ct-ink, #e8f1f4);
      }
      .swatch {
        width: 2.4rem;
        height: 2.4rem;
        border-radius: 50%;
        border: 1px solid
          color-mix(in srgb, var(--card-foreground, #e8f1f4) 30%, transparent);
        flex-shrink: 0;
      }
      .name {
        font-size: var(--boxel-font-size-xs, 0.7rem);
        letter-spacing: 0.3em;
      }
      .detail {
        margin-top: 0.25rem;
        font-size: 0.62rem;
        opacity: 0.55;
        letter-spacing: 0.08em;
      }
    </style>
  </template>
}
