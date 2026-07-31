// The card at grid/thumbnail sizes. Standard no-media composition, so this
// delegates to boxel-ui's FittedCard (which owns the fitted-card container
// queries, size quanta, and clamping) rather than hand-rolling the grid —
// per the fitted implementation standard in the boxel-skills repo
// (boxel/references/container-query-fitted-layout.md).
import { Component } from 'https://cardstack.com/base/card-api';
import { FittedCard } from '@cardstack/boxel-ui/components';
import { swatchStyle } from '../utils/munsell';
import type { ColorTree } from '../color-tree';

export class ColorTreeFitted extends Component<typeof ColorTree> {
  get hasLinkedTheme() {
    return Boolean((this.args.model as any)?.cardInfo?.theme);
  }

  <template>
    <div class='ct-fit {{unless this.hasLinkedTheme "ct-default"}}'>
      <FittedCard @titleTag='h3'>
        <:eyebrow>COLOR TREE</:eyebrow>
        <:title>{{if
            @model.selectedMunsell
            @model.selectedMunsell
            'Munsell solid'
          }}</:title>
        <:subtitle>{{if
            @model.selectedColor
            @model.selectedColor
            'no chip picked yet'
          }}</:subtitle>
        <:meta>
          <span
            class='swatch'
            style={{swatchStyle @model.selectedColor}}
          ></span>
        </:meta>
      </FittedCard>
    </div>

    <style scoped>
      .ct-fit {
        width: 100%;
        height: 100%;
        font-family: var(--font-mono, ui-monospace, 'SF Mono', monospace);
        letter-spacing: 0.08em;
      }
      /* themeless default: pin the card's night-sky brand as a MATCHED
         background/foreground pair. FittedCard paints with --card /
         --card-foreground; a linked theme supplies its own pair (this
         class is absent), so contrast is theme-authored either way. */
      .ct-default {
        --card: var(--ct-surface, #050a12);
        --card-foreground: var(--ct-ink, #e8f1f4);
        --muted-foreground: color-mix(
          in srgb,
          var(--ct-ink, #e8f1f4) 60%,
          transparent
        );
      }
      .swatch {
        width: 1.1rem;
        height: 1.1rem;
        border-radius: 50%;
        border: 1px solid
          color-mix(in srgb, var(--card-foreground, #22283f) 30%, transparent);
        flex-shrink: 0;
      }
    </style>
  </template>
}
