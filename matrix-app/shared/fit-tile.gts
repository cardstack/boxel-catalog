// Pretui — FitTile: a fitted view's rows, budgeted per fitted size.
import type { TemplateOnlyComponent } from '@ember/component/template-only';

// ── FitTile ──────────────────────────────────────────────────────────────
// The fitted-format half of delegated rendering. A card's fitted view hands
// FitTile its content in priority order — who (avatar, title, subtitle),
// state (status chips), one key fact, then relationships (linked cards in
// their atom format) — and FitTile packs as much of it as each fitted size
// can hold. Short sizes switch to compact type and spend width (state beside
// the title) before they drop anything; the avatar is decoration, so it is
// the first thing to go.
//
//   height    type     lines (250 wide)                 400 wide adds
//   ≥ 170     15 / 13  avatar·title / subline / state /  state beside title
//                      fact / relations
//   105–169   13 / 12  avatar·title / subline / state /  state beside title,
//                      fact                             relations line
//   65–104    13 / 12  title + state / subline
//   < 65      13       title + state
//
// Nothing is ever cropped, at three levels: a row that doesn't fit is not
// rendered, chips and atoms past the end of their line wrap out of sight
// whole, and a single item still too wide ellipsizes. The title always keeps
// at least 7rem. See ui-component/FITTED-RULE.md for the arithmetic.

export interface FitTileSignature {
  Element: HTMLElement;
  Blocks: {
    /** an Avatar at size 32; hidden under 250 wide and under 65 tall */
    avatar: [];
    title: [];
    subtitle: [];
    /** status chips, highest priority first; they compact inside small tiles */
    status: [];
    /** the one fact that explains the state ("Insurance until 31 Jan 2027") */
    fact: [];
    /** linked cards in their atom format, one line */
    relations: [];
  };
}

export const FitTile: TemplateOnlyComponent<FitTileSignature> = <template>
  <article class='pretui-fittile' data-test-pretui-fittile ...attributes>
    {{#if (has-block 'avatar')}}
      <span class='pretui-fittile-avatar'>{{yield to='avatar'}}</span>
    {{/if}}
    <span class='pretui-fittile-title'>{{yield to='title'}}</span>
    {{#if (has-block 'subtitle')}}
      <span class='pretui-fittile-subtitle'>{{yield to='subtitle'}}</span>
    {{/if}}
    {{#if (has-block 'status')}}
      <span class='pretui-fittile-status'>{{yield to='status'}}</span>
    {{/if}}
    {{#if (has-block 'fact')}}
      <span class='pretui-fittile-fact'>{{yield to='fact'}}</span>
    {{/if}}
    {{#if (has-block 'relations')}}
      <span class='pretui-fittile-relations'>{{yield to='relations'}}</span>
    {{/if}}
  </article>
  <style scoped>
    @layer PretComponent {
      /* Columns: avatar (collapses to 0 when hidden) · main (the title keeps
         at least 7rem) · side (state, up to its natural width). */
      .pretui-fittile {
        display: grid;
        grid-template-columns: auto minmax(7rem, 1fr) minmax(0, max-content);
        grid-template-areas:
          'avatar title title'
          'avatar subtitle subtitle'
          'status status status'
          'fact fact fact'
          'relations relations relations';
        align-content: start;
        align-items: center;
        column-gap: 0;
        row-gap: 0.5rem;
        block-size: 100%;
        box-sizing: border-box;
        padding: var(--boxel-sp-sm);
        overflow: hidden;
        font-size: 0.9375rem;
        line-height: 1.5;
        color: var(--card-foreground);
      }
      /* gaps live on the parts, so a hidden avatar leaves no empty gap */
      .pretui-fittile-avatar {
        grid-area: avatar;
        align-self: center;
        display: flex;
        margin-inline-end: var(--boxel-sp-sm);
      }
      .pretui-fittile-title {
        grid-area: title;
        font-weight: 600;
      }
      .pretui-fittile-subtitle {
        grid-area: subtitle;
        /* 2 below the title: the row gap less this pull */
        margin-block-start: -0.375rem;
        font-size: 0.8125rem;
        color: var(--muted-foreground);
      }
      .pretui-fittile-title,
      .pretui-fittile-subtitle,
      .pretui-fittile-fact {
        min-inline-size: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .pretui-fittile-fact {
        grid-area: fact;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
        font-variant-numeric: tabular-nums;
      }
      /* one line of chips or atoms: items past the line wrap out of sight
         whole; a lone item too wide for the line ellipsizes itself */
      .pretui-fittile-status,
      .pretui-fittile-relations {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 0.25rem;
        min-inline-size: 0;
        max-block-size: 1.375rem;
        overflow: hidden;
      }
      .pretui-fittile-status {
        grid-area: status;
      }
      .pretui-fittile-relations {
        grid-area: relations;
        font-size: 0.8125rem;
        max-block-size: 1.375rem;
      }

      /* 400 and wider: state moves beside the title, freeing its line */
      @container fitted-card (width >= 400px) {
        .pretui-fittile {
          grid-template-areas:
            'avatar title status'
            'avatar subtitle subtitle'
            'fact fact fact'
            'relations relations relations';
        }
        .pretui-fittile-status {
          justify-content: flex-end;
          margin-inline-start: var(--boxel-sp-sm);
        }
      }
      /* under 250 wide: the avatar goes first, it is decoration */
      @container fitted-card (width < 250px) {
        .pretui-fittile-avatar {
          display: none;
        }
      }

      /* 105 – 169 tall: compact type and tight lines buy a fourth line */
      @container fitted-card (height < 170px) {
        .pretui-fittile {
          padding: 0.5rem var(--boxel-sp-sm);
          row-gap: 0.25rem;
          font-size: 0.8125rem;
        }
        .pretui-fittile-subtitle {
          margin-block-start: -0.125rem;
          font-size: var(--boxel-font-size-xs);
        }
        .pretui-fittile-status {
          max-block-size: 1.125rem;
        }
        /* stays 22: a field's atom sits in Boxel's inline wrapper, whose
           text line adds descender space under a chip */
        .pretui-fittile-relations {
          font-size: var(--boxel-font-size-xs);
        }
      }
      @container fitted-card (height < 170px) and (width < 400px) {
        .pretui-fittile-relations {
          display: none;
        }
      }

      /* under 105 tall: title + state on one line, the subline below; the
         avatar gives its width to state */
      @container fitted-card (height < 105px) {
        .pretui-fittile {
          grid-template-areas:
            'avatar title status'
            'avatar subtitle subtitle';
          row-gap: 0.125rem;
        }
        .pretui-fittile-subtitle {
          margin-block-start: 0;
        }
        .pretui-fittile-avatar,
        .pretui-fittile-fact,
        .pretui-fittile-relations {
          display: none;
        }
        .pretui-fittile-status {
          justify-content: flex-end;
          margin-inline-start: 0.5rem;
        }
      }
      /* under 105 tall and 250 wide: the title needs the whole line */
      @container fitted-card (height < 105px) and (width < 250px) {
        .pretui-fittile-status {
          display: none;
        }
      }
      /* under 65 tall: one line */
      @container fitted-card (height < 65px) {
        .pretui-fittile-subtitle {
          display: none;
        }
      }
    }
  </style>
</template>;
