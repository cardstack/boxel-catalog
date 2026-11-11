// Compact record parts: the isolated / embedded / atom layouts a Matrix child
// module shares (header row, stat strip, two ruled columns, key-value rows).
// Fitted views use FitTile (cards/shared/fit-tile) with Mark and Dot from here.
import type { TemplateOnlyComponent } from '@ember/component/template-only';

/** A two-letter type mark ("Ce", "Qz"). */
export const Mark: TemplateOnlyComponent<{
  Args: { text?: string; small?: boolean };
}> = <template>
  <span class='mark {{if @small "sm"}}' aria-hidden='true'>{{@text}}</span>
  <style scoped>
    .mark {
      flex: none;
      display: inline-grid;
      place-items: center;
      inline-size: 1.375rem;
      block-size: 1.375rem;
      border-radius: calc(var(--radius) * 0.6);
      background-color: var(--muted);
      color: var(--foreground);
      font-family: var(--font-mono);
      font-size: var(--boxel-font-size-2xs);
      font-weight: 700;
    }
    .sm {
      inline-size: 1rem;
      block-size: 1rem;
    }
  </style>
</template>;

/** Status as dot + text. @hue: green · red · amber · blue · teal · slate. */
export const Dot: TemplateOnlyComponent<{
  Element: HTMLSpanElement;
  Args: { hue?: string };
  Blocks: { default: [] };
}> = <template>
  <span class='st' data-hue={{@hue}} ...attributes><span
      class='dot'
    ></span><span class='lbl'>{{yield}}</span></span>
  <style scoped>
    .st {
      display: inline-flex;
      align-items: center;
      gap: var(--boxel-sp-5xs);
      min-inline-size: 0;
      font-weight: 600;
      white-space: nowrap;
      --_dot-tone: var(--muted-foreground);
    }
    .st[data-hue='green'] {
      --_dot-tone: var(--success);
    }
    .st[data-hue='red'] {
      --_dot-tone: var(--destructive);
    }
    .st[data-hue='amber'] {
      --_dot-tone: var(--warning);
    }
    .st[data-hue='blue'] {
      --_dot-tone: var(--chart-1);
    }
    .st[data-hue='teal'] {
      --_dot-tone: var(--chart-2);
    }
    .dot {
      flex: none;
      inline-size: 0.4375rem;
      block-size: 0.4375rem;
      border-radius: 50%;
      background-color: var(--_dot-tone);
    }
    .lbl {
      overflow: hidden;
      text-overflow: ellipsis;
    }
  </style>
</template>;

// A numeric 0 is a value, not a missing one.
function orDash(v?: string | number | null) {
  return v == null || v === '' ? '—' : v;
}

/** One tile of the stat strip. */
export const Stat: TemplateOnlyComponent<{
  Args: { label: string; value?: string | number | null; sub?: string | null };
}> = <template>
  <div class='stat'>
    <span class='cap'><span class='dot'></span>{{@label}}</span>
    <span class='num'>{{orDash @value}}</span>
    <span class='sub'>{{@sub}}</span>
  </div>
  <style scoped>
    .stat {
      display: flex;
      flex-direction: column;
      gap: var(--boxel-sp-6xs);
      min-inline-size: 0;
      padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
      border-inline-end: 1px solid var(--border);
      border-block-end: 1px solid var(--border);
      /* the strip clips the outer right and bottom lines */
      margin-inline-end: -1px;
      margin-block-end: -1px;
    }
    .cap {
      display: inline-flex;
      align-items: center;
      gap: var(--boxel-sp-5xs);
      font-family: var(--font-mono);
      font-size: var(--boxel-font-size-2xs);
      font-weight: 600;
      letter-spacing: 0.13em;
      text-transform: uppercase;
      color: var(--muted-foreground);
    }
    .dot {
      inline-size: 0.375rem;
      block-size: 0.375rem;
      border-radius: 50%;
      background-color: var(--muted-foreground);
    }
    .num {
      font-size: var(--boxel-font-size-lg);
      font-weight: 700;
      line-height: 1.1;
      font-variant-numeric: tabular-nums;
    }
    .sub {
      min-block-size: 1em;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      font-size: var(--boxel-font-size-2xs);
      color: var(--muted-foreground);
    }
  </style>
</template>;

/** A flat section with a small bold title, ruled from the one above. */
export const Section: TemplateOnlyComponent<{
  Args: { title: string };
  Blocks: { default: [] };
}> = <template>
  <section class='sec'>
    <h2>{{@title}}</h2>
    {{yield}}
  </section>
  <style scoped>
    h2 {
      padding: var(--boxel-sp-xs) var(--boxel-sp-sm) var(--boxel-sp-4xs);
      font-family: var(--font-sans);
      font-size: var(--boxel-font-size-xs);
      font-weight: 700;
      letter-spacing: normal;
      text-transform: none;
      color: var(--card-foreground);
    }
  </style>
</template>;

/** One ruled key-value row; @mono for ids, dates, counts. */
export const Kv: TemplateOnlyComponent<{
  Args: { label: string; mono?: boolean };
  Blocks: { default: [] };
}> = <template>
  <div class='kv'>
    <span class='k'>{{@label}}</span>
    <span class='v {{if @mono "mono"}}'>{{yield}}</span>
  </div>
  <style scoped>
    .kv {
      display: grid;
      grid-template-columns: minmax(6rem, 7.5rem) minmax(0, 1fr);
      align-items: center;
      gap: var(--boxel-sp-xs);
      min-block-size: 1.75rem;
      padding: 0 var(--boxel-sp-sm);
      border-block-start: 1px solid var(--border);
    }
    .k {
      font-size: var(--boxel-font-size-2xs);
      color: var(--muted-foreground);
    }
    .v {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--boxel-sp-5xs) var(--boxel-sp-xs);
      min-inline-size: 0;
      overflow-wrap: break-word;
    }
    .mono {
      font-family: var(--font-mono);
      font-size: var(--boxel-font-size-2xs);
      font-variant-numeric: tabular-nums;
    }
  </style>
</template>;

/** Isolated layout: header row, stat strip, main column + side column. */
export const Sheet: TemplateOnlyComponent<{
  Args: { mark?: string; title?: string; meta?: string };
  Blocks: {
    status: [];
    actions: [];
    stats: [];
    main: [];
    side: [];
  };
}> = <template>
  <article class='sheet'>
    <header class='head'>
      <div class='who'>
        <Mark @text={{@mark}} />
        <div class='id'>
          <h1>{{@title}}</h1>
          {{#if @meta}}<p class='meta'>{{@meta}}</p>{{/if}}
        </div>
      </div>
      <div class='bar'>
        {{#if (has-block 'status')}}{{yield to='status'}}{{/if}}
        {{#if (has-block 'actions')}}{{yield to='actions'}}{{/if}}
      </div>
    </header>
    {{#if (has-block 'stats')}}
      <div class='stats'>{{yield to='stats'}}</div>
    {{/if}}
    <div class='cols'>
      <div class='main'>{{yield to='main'}}</div>
      {{#if (has-block 'side')}}
        <aside class='side'>{{yield to='side'}}</aside>
      {{/if}}
    </div>
  </article>
  <style scoped>
    .sheet {
      container-type: inline-size;
      min-block-size: 100%;
      box-sizing: border-box;
      font-family: var(--font-sans);
      font-size: var(--boxel-font-size-xs);
      line-height: 1.4;
      color: var(--card-foreground);
      background-color: var(--card);
      overflow-y: auto;
    }
    .head {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      justify-content: space-between;
      gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
      padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
      border-block-end: 1px solid var(--border);
    }
    .who {
      display: flex;
      align-items: center;
      gap: var(--boxel-sp-xs);
      min-inline-size: 0;
    }
    .id {
      min-inline-size: 0;
    }
    h1 {
      font-family: var(--font-sans);
      font-size: var(--boxel-font-size-sm);
      font-weight: 700;
      letter-spacing: normal;
      text-transform: none;
    }
    .meta {
      font-size: var(--boxel-font-size-2xs);
      color: var(--muted-foreground);
    }
    .bar {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
    }
    /* every tile draws right + bottom; the strip clips the outer edges */
    .stats {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(10rem, 1fr));
      overflow: hidden;
    }
    .cols {
      display: grid;
      grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
      border-block-start: 1px solid var(--border);
    }
    .main,
    .side {
      min-inline-size: 0;
      padding-block-end: var(--boxel-sp-xs);
    }
    .side {
      border-inline-start: 1px solid var(--border);
    }
    @container (max-width: 40rem) {
      .cols {
        grid-template-columns: minmax(0, 1fr);
      }
      .side {
        border-inline-start: 0;
        border-block-start: 1px solid var(--border);
      }
    }
  </style>
</template>;

/** Embedded layout: header line, one fact line, then ruled rows. */
export const Embed: TemplateOnlyComponent<{
  Args: { mark?: string; title?: string; meta?: string };
  Blocks: { status: []; fact: []; default: [] };
}> = <template>
  <article class='emb'>
    <header class='head'>
      <Mark @text={{@mark}} />
      <div class='id'>
        <h3>{{@title}}</h3>
        {{#if @meta}}<p class='meta'>{{@meta}}</p>{{/if}}
      </div>
      {{#if (has-block 'status')}}
        <div class='bar'>{{yield to='status'}}</div>
      {{/if}}
    </header>
    {{#if (has-block 'fact')}}
      <p class='fact'>{{yield to='fact'}}</p>
    {{/if}}
    {{yield}}
  </article>
  <style scoped>
    .emb {
      container-type: inline-size;
      font-family: var(--font-sans);
      font-size: var(--boxel-font-size-xs);
      line-height: 1.4;
      color: var(--card-foreground);
      background-color: var(--card);
    }
    .head {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--boxel-sp-xs);
      padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
    }
    .id {
      flex: 1;
      min-inline-size: 0;
    }
    h3 {
      font-size: var(--boxel-font-size-sm);
      font-weight: 700;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .meta {
      font-size: var(--boxel-font-size-2xs);
      color: var(--muted-foreground);
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .bar {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--boxel-sp-xs);
    }
    @container (max-width: 22rem) {
      .bar {
        flex-basis: 100%;
      }
    }
    .fact {
      padding: var(--boxel-sp-5xs) var(--boxel-sp-sm);
      border-block-start: 1px solid var(--border);
      line-height: 1.75rem;
    }
  </style>
</template>;

/** Atom: mark + name + optional status; the name ellipsises first. */
export const AtomChip: TemplateOnlyComponent<{
  Args: { mark?: string; title?: string };
  Blocks: { default: [] };
}> = <template>
  <span class='atom'>
    <Mark @text={{@mark}} @small={{true}} />
    <span class='name'>{{@title}}</span>
    {{#if (has-block)}}<span class='side'>{{yield}}</span>{{/if}}
  </span>
  <style scoped>
    .atom {
      display: inline-flex;
      align-items: center;
      gap: var(--boxel-sp-5xs);
      max-inline-size: 100%;
      min-inline-size: 0;
      font-size: var(--boxel-font-size-xs);
      vertical-align: middle;
    }
    .name {
      min-inline-size: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      font-weight: 600;
    }
    .side {
      flex: none;
      font-size: var(--boxel-font-size-2xs);
    }
  </style>
</template>;
