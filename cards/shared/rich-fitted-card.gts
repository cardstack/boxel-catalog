import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
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
//
// A card led by an image passes `media` (see Media). Its box depends only on
// the container, never on the image, so nothing moves when it loads:
//
//   thumb   under 170 tall          a square at the start, at most 4rem and 35% of the width
//   hero    under 400 wide, 170+    on top, 45% of the height
//   side    400 wide, 170 – 444     at the start, 40% of the width
//   banner  400 wide, 445+          on top, 40% of the height
//
// A block that renders nothing (an empty value, a false {{#if}}) takes no
// room: every tier is hidden while it is :empty.

export interface RichFittedCardSignature {
  Element: HTMLElement;
  Blocks: {
    /** the card's image, see Media; replaces the avatar */
    media: [];
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
    <article
      class='rfc'
      data-rich-fitted-card
      data-media={{if (has-block 'media') 'true'}}
      ...attributes
    >
      {{#if (has-block 'media')}}
        <div class='rfc-media'>{{yield to='media'}}</div>
      {{/if}}
      <div class='rfc-body'>
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
      </div>
    </article>
    <style scoped>
      @layer PretComponent {
        /* The media, when there is one, then the body: a column of tiers, the
           head (avatar, title, status, subtitle), the fact, the metric, the
           details, which take the height that is left, and the relations. */
        .rfc {
          --rfc-row: 1.5rem;
          --pretui-avatar-size: 1.25rem;
          display: flex;
          gap: var(--boxel-sp-xs);
          box-sizing: border-box;
          block-size: 100%;
          padding: var(--boxel-sp-xs);
          overflow: hidden;
          font-size: var(--boxel-font-size-xs);
          line-height: 1.25;
          color: var(--card-foreground);
        }
        .rfc-body {
          flex: 1 1 0;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-3xs);
          min-inline-size: 0;
          min-block-size: 0;
        }
        .rfc-body > * {
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
        /* a size container too, so a Detail can hide itself while the box
           is shorter than one row (a repeat always makes at least one track) */
        .rfc-details {
          container: rfc-details / size;
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
            grid-template-columns: auto minmax(min(4.5rem, 100%), 1fr) minmax(
                min-content,
                max-content
              );
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
          }
          .rfc-body {
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
            grid-template-columns: auto minmax(min(4.5rem, 100%), 1fr) minmax(
                min-content,
                max-content
              );
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

        /* a block that renders nothing takes no room */
        .rfc-avatar:empty,
        .rfc-status:empty,
        .rfc-subtitle:empty,
        .rfc-fact:empty,
        .rfc-metric:empty,
        .rfc-details:empty,
        .rfc-relations:empty,
        .rfc-media:empty {
          display: none;
        }

        /* media: a thumbnail by default; the image replaces the avatar */
        .rfc-media {
          flex: none;
          position: relative;
          overflow: hidden;
          align-self: flex-start;
          aspect-ratio: 1;
          block-size: min(100%, 35cqi, 4rem);
          border-radius: var(--radius);
          background: var(--muted);
        }
        .rfc[data-media] .rfc-avatar {
          display: none;
        }
        /* hero: under 400 wide from 170 tall, the image on top */
        @container fitted-card (width < 400px) and (height >= 170px) {
          .rfc[data-media] {
            flex-direction: column;
          }
          .rfc[data-media] .rfc-media {
            align-self: stretch;
            aspect-ratio: auto;
            block-size: 45cqb;
          }
          .rfc[data-media] .rfc-relations {
            display: none;
          }
        }
        @container fitted-card (width < 400px) and (height >= 170px) and (height < 275px) {
          .rfc[data-media] .rfc-metric,
          .rfc[data-media] .rfc-fact {
            display: none;
          }
        }
        /* side: 400 wide, 170 to 444 tall, the image at the start; the body is
           narrow, so the head keeps the status on a line of its own */
        @container fitted-card (width >= 400px) and (height >= 170px) and (height < 445px) {
          .rfc[data-media] .rfc-media {
            align-self: stretch;
            aspect-ratio: auto;
            block-size: auto;
            inline-size: 40%;
          }
          .rfc[data-media] .rfc-head {
            grid-template-columns: auto minmax(0, 1fr);
            grid-template-areas:
              'avatar title'
              'avatar subtitle'
              'status status';
          }
          .rfc[data-media] .rfc-status {
            justify-content: flex-start;
            margin-inline-start: 0;
          }
          .rfc[data-media] .rfc-relations {
            display: none;
          }
        }
        /* banner: 400 wide from 445 tall, the image on top */
        @container fitted-card (width >= 400px) and (height >= 445px) {
          .rfc[data-media] {
            flex-direction: column;
          }
          .rfc[data-media] .rfc-media {
            align-self: stretch;
            aspect-ratio: auto;
            block-size: 40cqb;
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
    <span class='rfc-detail-v'>{{#if
        @value
      }}{{@value}}{{else}}{{yield}}{{/if}}</span>
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
      /* the details box is shorter than one row: no half row */
      @container rfc-details (height < 1.5rem) {
        .rfc-detail {
          display: none;
        }
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

interface MediaSignature {
  Args: {
    src?: string | null;
    /** required; '' when the image only decorates */
    alt: string;
  };
  /** the placeholder, usually the card's own icon */
  Blocks: { default: [] };
  Element: HTMLImageElement;
}

/** The content of the `media` block. The placeholder is always drawn and the
 *  image lies over it, so a missing or broken image shows the placeholder,
 *  even in prerendered HTML where no handler runs. */
export class Media extends Component<MediaSignature> {
  @tracked failed = false;
  fail = () => {
    this.failed = true;
  };

  <template>
    <span class='rfc-media-ph' aria-hidden='true'>{{yield}}</span>
    {{#if @src}}
      {{#unless this.failed}}
        <img
          class='rfc-media-img'
          src={{@src}}
          alt={{@alt}}
          loading='lazy'
          {{on 'error' this.fail}}
          ...attributes
        />
      {{/unless}}
    {{/if}}
    <style scoped>
      @layer PretComponent {
        .rfc-media-ph {
          position: absolute;
          inset: 0;
          display: grid;
          place-items: center;
          color: var(--muted-foreground);
        }
        /* a broken image paints nothing of its own over the placeholder */
        .rfc-media-img {
          position: absolute;
          inset: 0;
          inline-size: 100%;
          block-size: 100%;
          object-fit: cover;
          color: transparent;
          font-size: 0;
        }
      }
    </style>
  </template>
}
