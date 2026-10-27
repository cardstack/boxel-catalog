// Pretui — PageScaffold: a page's title block, stat row and sections.
import GlimmerComponent from '@glimmer/component';
import { guidFor } from '@ember/object/internals';
import { Stat } from './stat';
import type { PretuiToneArg } from '../pretui-primitives';

export interface PageStat {
  label: string;
  value: number | string;
  hint?: string;
  hintTone?: PretuiToneArg;
}

interface PageScaffoldSignature {
  Args: {
    eyebrow?: string;
    title?: string;
    /** a live line under the title: what is waiting, what is blocked */
    subtitle?: string;
    /** set the title in the mono register document numbers use */
    mono?: boolean;
    stats?: PageStat[];
  };
  Blocks: {
    /** an Avatar or a sidebar trigger before the title */
    lead: [];
    chips: [];
    actions: [];
    /** flashes and notes between the header and the stat row */
    alerts: [];
    default: [];
  };
  Element: HTMLElement;
}

// PageScaffold: a title block with a live subtitle, chips and actions, a
// Stat row, then the page's sections. An app page and the isolated records
// it opens share it, so they read as one system. The root is the page: it
// scrolls itself and draws no frame. Spacing comes from the --boxel-sp ladder:
// page padding --boxel-sp-lg (--boxel-sp when narrow), sections --boxel-sp-lg
// apart, title at the large ladder size, subtitle sm, section heading base,
// stat tiles padded --boxel-sp and --boxel-sp apart.
// Knobs: --pretui-page-title-color (the h1, default the inherited colour),
// --pretui-page-stat-border (default 1px solid var(--border)) and
// --pretui-page-stat-shadow (default none) for the stat tiles.
export class PageScaffold extends GlimmerComponent<PageScaffoldSignature> {
  <template>
    <article class='pretui-page' data-test-pretui-page ...attributes>
      <header class='pretui-page-head'>
        {{#if (has-block 'lead')}}
          <div class='pretui-page-lead'>{{yield to='lead'}}</div>
        {{/if}}
        <div class='pretui-page-title'>
          {{#if @eyebrow}}<p class='pretui-page-eyebrow'>{{@eyebrow}}</p>{{/if}}
          <h1 class={{if @mono 'pretui-page-mono'}}>{{@title}}</h1>
          {{#if @subtitle}}
            <p class='pretui-page-sub' role='status'>{{@subtitle}}</p>
          {{/if}}
          {{#if (has-block 'chips')}}
            <div class='pretui-page-chips'>{{yield to='chips'}}</div>
          {{/if}}
        </div>
        {{#if (has-block 'actions')}}
          <div class='pretui-page-actions'>{{yield to='actions'}}</div>
        {{/if}}
      </header>
      {{yield to='alerts'}}
      {{#if @stats.length}}
        <ul class='pretui-page-stats' aria-label='Summary'>
          {{#each @stats as |s|}}
            <li class='pretui-page-stat'><Stat
                @label={{s.label}}
                @value={{s.value}}
                @hint={{s.hint}}
                @hintTone={{s.hintTone}}
                @roll={{false}}
              /></li>
          {{/each}}
        </ul>
      {{/if}}
      {{yield}}
    </article>
    <style scoped>
      @layer PretComponent {
        .pretui-page {
          container-type: inline-size;
          height: 100%;
          overflow-y: auto;
          /* grid, not a flex column: a flex column shrinks an overflow:hidden
             child (a Panel) to fit instead of letting the page scroll */
          display: grid;
          grid-template-columns: minmax(0, 1fr);
          grid-auto-rows: max-content;
          align-content: start;
          gap: var(--boxel-sp-lg);
          padding: var(--boxel-sp-lg);
          font-size: var(--boxel-font-size-sm);
          line-height: 1.5;
        }
        .pretui-page-head {
          display: flex;
          flex-wrap: wrap;
          align-items: flex-end;
          gap: var(--boxel-sp);
        }
        .pretui-page-lead {
          flex: none;
          align-self: center;
        }
        .pretui-page-title {
          flex: 1;
          min-width: 0;
          display: grid;
          gap: var(--boxel-sp-6xs);
        }
        .pretui-page-title h1 {
          font-size: var(--boxel-font-size-lg);
          font-weight: 600;
          line-height: 1.25;
          color: var(--pretui-page-title-color, currentColor);
        }
        .pretui-page-eyebrow,
        .pretui-page-sub {
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .pretui-page-eyebrow {
          font-size: var(--boxel-font-size-xs);
        }
        .pretui-page-mono {
          font-family: var(--font-mono);
        }
        .pretui-page-chips,
        .pretui-page-actions {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs);
        }
        .pretui-page-chips {
          margin-top: var(--boxel-sp-4xs);
        }
        .pretui-page-stats {
          --_page-stat-min: 10rem;
          display: grid;
          grid-template-columns: repeat(
            auto-fit,
            minmax(var(--_page-stat-min), 1fr)
          );
          gap: var(--boxel-sp);
          margin: 0;
          padding: 0;
          list-style: none;
        }
        .pretui-page-stat {
          padding: var(--boxel-sp);
          border-radius: var(--boxel-border-radius-lg);
          background-color: var(--card);
          /* Card's outlined recipe, so a tile still reads on a page the
             same colour as --card */
          border: var(--pretui-page-stat-border, 1px solid var(--border));
          box-shadow: var(--pretui-page-stat-shadow, none);
          color: var(--foreground);
        }
        @container (width < 40rem) {
          .pretui-page {
            padding: var(--boxel-sp);
          }
          .pretui-page-actions {
            width: 100%;
          }
        }
      }
    </style>
  </template>
}

interface PageSectionSignature {
  Args: { title: string; hint?: string };
  Blocks: { default: []; aside: [] };
  Element: HTMLElement;
}

export class PageSection extends GlimmerComponent<PageSectionSignature> {
  headingId = `${guidFor(this)}-title`;
  <template>
    <section
      class='pretui-section'
      data-test-pretui-page-section
      aria-labelledby={{this.headingId}}
      ...attributes
    >
      <div class='pretui-section-head'>
        <h2 id={{this.headingId}}>{{@title}}</h2>
        {{#if @hint}}<p class='pretui-section-hint'>{{@hint}}</p>{{/if}}
        {{yield to='aside'}}
      </div>
      {{yield}}
    </section>
    <style scoped>
      @layer PretComponent {
        .pretui-section {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
          min-width: 0;
        }
        .pretui-section-head {
          display: flex;
          flex-wrap: wrap;
          align-items: baseline;
          justify-content: space-between;
          gap: var(--boxel-sp-sm);
        }
        .pretui-section-head h2 {
          font-size: var(--boxel-font-size);
          font-weight: 600;
          line-height: 1.5;
        }
        .pretui-section-hint {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      }
    </style>
  </template>
}
