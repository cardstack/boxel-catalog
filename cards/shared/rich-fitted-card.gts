import type { TemplateOnlyComponent } from '@ember/component/template-only';

// ── RichFittedCard ───────────────────────────────────────────────────────
// The one fitted layout for every Matrix card. A card hands it content by
// role, highest priority first, and RichFittedCard shows as many tiers as the
// fitted size can hold. Nothing is ever cropped: a tier that does not fit is
// not rendered, a detail row is shown whole or not at all, and a single value
// that is too wide ellipsizes.
//
//   tier 1  avatar, title, status, metric   top of the card; type steps up
//                                           as the container grows
//   tier 2  subtitle, fact                  one line each
//   tier 3  details                         key-value rows, anchored to the
//                                           bottom, dropped from the bottom up
//   tier 4  relations                       linked cards in their atom format
//
//   height     shown (250 wide)                                   400 wide
//   < 65       title                                              + status
//   65 – 104   title, subtitle                                    + status
//   105 – 169  title, status, subtitle, fact
//   170 – 249  + metric, details                                  status beside title
//   ≥ 250      + relations
//
//   width < 250: the avatar goes first, it is decoration; under 105 tall the
//   status goes too, so the title keeps the whole line.

export interface RichFittedCardSignature {
  Element: HTMLElement;
  Blocks: {
    /** an Avatar or a type mark; hidden under 250 wide */
    avatar: [];
    title: [];
    /** state: a dot and text, or chips; items past the end of the line wrap out of sight whole */
    status: [];
    /** a big number with its caption, see Metric */
    metric: [];
    subtitle: [];
    /** the one line that explains the state */
    fact: [];
    /** key-value rows, one Detail each; they sit at the bottom of the card */
    details: [];
    /** linked cards in their atom format, one line */
    relations: [];
  };
}

export const RichFittedCard: TemplateOnlyComponent<RichFittedCardSignature> =
  <template>
    <article class='rfc' data-rich-fitted-card ...attributes>
      <div class='rfc-head'>
        {{#if (has-block 'avatar')}}
          <span class='rfc-avatar'>{{yield to='avatar'}}</span>
        {{/if}}
        <span class='rfc-title'>{{yield to='title'}}</span>
        {{#if (has-block 'status')}}
          <span class='rfc-status'>{{yield to='status'}}</span>
        {{/if}}
        {{#if (has-block 'subtitle')}}
          <span class='rfc-subtitle'>{{yield to='subtitle'}}</span>
        {{/if}}
      </div>
      {{#if (has-block 'fact')}}
        <span class='rfc-fact'>{{yield to='fact'}}</span>
      {{/if}}
      {{#if (has-block 'metric')}}
        <div class='rfc-metric'>{{yield to='metric'}}</div>
      {{/if}}
      {{#if (has-block 'details')}}
        <div class='rfc-details'>{{yield to='details'}}</div>
      {{/if}}
      {{#if (has-block 'relations')}}
        <span class='rfc-relations'>{{yield to='relations'}}</span>
      {{/if}}
    </article>
    <style scoped>
      @layer PretComponent {
        /* A column of tiers: the head (avatar, title, status, subtitle), the
           fact, the metric, the details, which take the height that is left,
           and the relations. */
        .rfc {
          --rfc-row: 1.5rem;
          --pretui-avatar-size: 1.25rem;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-3xs);
          box-sizing: border-box;
          block-size: 100%;
          padding: var(--boxel-sp-xs);
          overflow: hidden;
          font-size: var(--boxel-font-size-xs);
          line-height: 1.25;
          color: var(--card-foreground);
        }
        .rfc > * {
          flex: none;
          min-inline-size: 0;
        }
        /* Head, under 400 wide: the avatar spans the title and subtitle lines
           and the status has a line of its own. */
        .rfc-head {
          display: grid;
          grid-template-columns: auto minmax(0, 1fr);
          grid-template-areas:
            'avatar title'
            'avatar subtitle'
            'status status';
          align-items: center;
          row-gap: var(--boxel-sp-3xs);
        }
        /* the gap lives on the avatar, so a hidden avatar leaves none */
        .rfc-avatar {
          grid-area: avatar;
          align-self: center;
          display: flex;
          line-height: 0;
          margin-inline-end: var(--boxel-sp-2xs);
        }
        .rfc-title {
          grid-area: title;
          font-weight: 700;
        }
        .rfc-subtitle {
          grid-area: subtitle;
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .rfc-fact {
          color: var(--foreground);
          font-variant-numeric: tabular-nums;
        }
        .rfc-title,
        .rfc-subtitle,
        .rfc-fact {
          min-inline-size: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .rfc-status,
        .rfc-relations {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          min-inline-size: 0;
          max-block-size: 1.25rem;
          overflow: hidden;
        }
        .rfc-status {
          grid-area: status;
        }
        .rfc-relations {
          display: none;
        }
        .rfc-metric {
          display: none;
          align-items: baseline;
          gap: var(--boxel-sp-2xs);
          min-inline-size: 0;
          overflow: hidden;
          white-space: nowrap;
        }
        /* whole rows only: one track per full row that fits, any further row
           lands in a zero-height track; the rows pack to the bottom */
        .rfc-details {
          flex: 1 1 0;
          display: none;
          grid-template-rows: repeat(auto-fit, var(--rfc-row));
          grid-auto-rows: 0;
          align-content: end;
          min-block-size: 0;
          overflow: hidden;
        }

        /* 400 and wider: the status moves beside the title */
        @container fitted-card (width >= 400px) {
          .rfc-head {
            grid-template-columns: auto minmax(0, 1fr) auto;
            grid-template-areas:
              'avatar title status'
              'avatar subtitle subtitle';
          }
          .rfc-status {
            justify-content: flex-end;
            margin-inline-start: var(--boxel-sp-xs);
          }
        }
        /* under 250 wide the avatar goes first, it is decoration */
        @container fitted-card (width < 250px) {
          .rfc-avatar {
            display: none;
          }
        }

        /* 170 and taller: the metric and the detail rows join in */
        @container fitted-card (height >= 170px) {
          .rfc {
            padding: var(--boxel-sp-sm);
            gap: var(--boxel-sp-2xs);
          }
          .rfc-metric {
            display: flex;
          }
          .rfc-details {
            display: grid;
          }
        }
        /* 250 and taller: the relations line fits under the details */
        @container fitted-card (height >= 250px) {
          .rfc-relations {
            display: flex;
          }
        }
        /* the top tier steps up with the container */
        @container fitted-card (height >= 250px) {
          .rfc {
            --pretui-avatar-size: 1.5rem;
          }
          .rfc-title {
            font-size: var(--boxel-font-size-sm);
          }
          .rfc-subtitle {
            font-size: var(--boxel-font-size-xs);
          }
        }
        @container fitted-card (width >= 400px) and (height >= 170px) {
          .rfc {
            --pretui-avatar-size: 1.5rem;
          }
          .rfc-title {
            font-size: var(--boxel-font-size-sm);
          }
          .rfc-subtitle {
            font-size: var(--boxel-font-size-xs);
          }
        }

        /* under 105 tall: title and status on one line, the subtitle below */
        @container fitted-card (height < 105px) {
          .rfc-head {
            grid-template-columns: auto minmax(0, 1fr) auto;
            grid-template-areas:
              'avatar title status'
              'avatar subtitle subtitle';
            row-gap: var(--boxel-sp-5xs);
          }
          .rfc-fact,
          .rfc-metric,
          .rfc-details,
          .rfc-relations {
            display: none;
          }
          .rfc-status {
            justify-content: flex-end;
            margin-inline-start: var(--boxel-sp-xs);
          }
        }
        /* under 105 tall and 250 wide: the title needs the whole line */
        @container fitted-card (height < 105px) and (width < 250px) {
          .rfc-status {
            display: none;
          }
        }
        /* under 65 tall: one line */
        @container fitted-card (height < 65px) {
          .rfc-head {
            grid-template-areas: 'avatar title status';
            row-gap: 0;
          }
          .rfc-subtitle {
            display: none;
          }
        }
      }
    </style>
  </template>;

interface MetricSignature {
  Args: { value?: string | null; label?: string | null };
  Element: HTMLSpanElement;
}

/** The content of the `metric` block: a big number and its caption. */
export const Metric: TemplateOnlyComponent<MetricSignature> = <template>
  <span class='rfc-metric-v' ...attributes>{{@value}}</span>
  {{#if @label}}<span class='rfc-metric-l'>{{@label}}</span>{{/if}}
  <style scoped>
    @layer PretComponent {
      .rfc-metric-v {
        font-size: var(--boxel-font-size-lg);
        line-height: 1.25;
        font-weight: 700;
        font-variant-numeric: tabular-nums;
      }
      .rfc-metric-l {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
    }
  </style>
</template>;

interface DetailSignature {
  Args: { label: string; value?: string | null };
  Blocks: { default: [] };
  Element: HTMLElement;
}

/** One row of the `details` block: a mono caps label and its value. The value
 *  is the `value` argument, or the block when it holds an atom. */
export const Detail: TemplateOnlyComponent<DetailSignature> = <template>
  <div class='rfc-detail' ...attributes>
    <span class='rfc-detail-k'>{{@label}}</span>
    <span class='rfc-detail-v'>{{#if @value}}{{@value}}{{else}}{{yield}}{{/if}}</span>
  </div>
  <style scoped>
    @layer PretComponent {
      .rfc-detail {
        box-sizing: border-box;
        block-size: 100%;
        min-block-size: 0;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-xs);
        overflow: hidden;
      }
      .rfc-detail-k {
        flex: none;
        font-family: var(--font-mono);
        font-size: 0.5625rem; /* 9px ladder label: no token */
        font-weight: 600;
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .rfc-detail-v {
        min-inline-size: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        text-align: end;
        font-variant-numeric: tabular-nums;
      }
      /* rules between rows only where there is room for them; an inset
         shadow, so a row in a zero-height track draws no stray line */
      @container fitted-card (height >= 250px) {
        .rfc-detail {
          box-shadow: inset 0 1px 0 var(--border);
        }
      }
    }
  </style>
</template>;
