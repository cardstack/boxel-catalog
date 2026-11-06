// The compact record layout every service-desk card's isolated and embedded
// formats share: one bordered card, flat ruled sections, mono-caps labels.
import type { TemplateOnlyComponent } from '@ember/component/template-only';

export const RecCard: TemplateOnlyComponent<{
  Args: { inset?: boolean };
  Blocks: { default: [] };
  Element: HTMLElement;
}> = <template>
  <article class='rec {{if @inset "inset"}}' ...attributes>{{yield}}</article>
  <style scoped>
    .rec {
      container-type: inline-size;
      border: 1px solid var(--border);
      border-radius: var(--radius);
      background: var(--card);
      color: var(--card-foreground);
      font-family: var(--font-sans);
      font-size: 0.75rem;
    }
    .inset {
      margin: 0;
    }
  </style>
</template>;

export const RecHead: TemplateOnlyComponent<{
  Args: { mark: string; title?: string; sub?: string };
  Blocks: { default: []; status: [] };
}> = <template>
  <header class='head'>
    <span class='mark' aria-hidden='true'>{{@mark}}</span>
    <span class='id'>
      <span class='t'>{{@title}}</span>
      {{#if @sub}}<span class='s'>{{@sub}}</span>{{/if}}
    </span>
    {{#if (has-block 'status')}}<span class='sts'>{{yield
          to='status'
        }}</span>{{/if}}
    {{yield}}
  </header>
  <style scoped>
    .head {
      display: flex;
      align-items: center;
      gap: 0.625rem;
      padding: 0.625rem;
      flex-wrap: wrap;
    }
    .mark {
      flex: none;
      display: grid;
      place-items: center;
      inline-size: 1.75rem;
      block-size: 1.75rem;
      border: 1px solid var(--border);
      font: 600 0.625rem/1 var(--font-mono);
    }
    .id {
      flex: 1 1 12rem;
      min-inline-size: 0;
      display: grid;
      gap: 0.125rem;
    }
    .t {
      font-weight: 700;
    }
    .s {
      font-size: 0.6875rem;
      color: var(--muted-foreground);
    }
    .sts {
      display: flex;
      gap: 0.75rem;
      flex-wrap: wrap;
    }
  </style>
</template>;

/** Joined stat strip; each child is a Stat. Divided-grid lines. */
export const RecStats: TemplateOnlyComponent<{
  Blocks: { default: [] };
}> = <template>
  <section class='stats'>{{yield}}</section>
  <style scoped>
    .stats {
      --text-stat: 1.375rem;
      display: grid;
      grid-auto-flow: column;
      grid-auto-columns: minmax(0, 1fr);
      border-block-start: 1px solid var(--border);
      padding: 0.4375rem 0.625rem;
      gap: 1.25rem;
    }
  </style>
</template>;

export const RecBody: TemplateOnlyComponent<{
  Blocks: { main: []; side: [] };
}> = <template>
  <div class='body'>
    <div class='main'>{{yield to='main'}}</div>
    <aside class='side'>{{yield to='side'}}</aside>
  </div>
  <style scoped>
    .body {
      display: grid;
      grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
      border-block-start: 1px solid var(--border);
    }
    .main,
    .side {
      min-inline-size: 0;
    }
    .side {
      border-inline-start: 1px solid var(--border);
    }
    @container (width <= 44rem) {
      .body {
        grid-template-columns: minmax(0, 1fr);
      }
      .side {
        border-inline-start: none;
        border-block-start: 1px solid var(--border);
      }
    }
  </style>
</template>;

export const RecBlock: TemplateOnlyComponent<{
  Args: { title?: string };
  Blocks: { default: [] };
}> = <template>
  <section class='blk'>
    {{#if @title}}<h2 class='sh'>{{@title}}</h2>{{/if}}
    {{yield}}
  </section>
  <style scoped>
    .blk + .blk,
    .blk {
      border-block-end: 1px solid var(--border);
    }
    .blk:last-child {
      border-block-end: none;
    }
    .sh {
      margin: 0;
      padding: 0.4375rem 0.625rem;
      font-family: var(--font-sans);
      font-size: 0.75rem;
      font-weight: 700;
      text-transform: none;
      letter-spacing: normal;
    }
  </style>
</template>;

/** One ruled key-value row: 9px mono caps label, value wraps (atoms never crop). */
export const RecRow: TemplateOnlyComponent<{
  Args: { label: string; mono?: boolean };
  Blocks: { default: [] };
}> = <template>
  <div class='row'>
    <span class='k'>{{@label}}</span>
    <span class='v {{if @mono "mono"}}'>{{yield}}</span>
  </div>
  <style scoped>
    .row {
      display: grid;
      grid-template-columns: 7.5rem minmax(0, 1fr);
      align-items: center;
      min-block-size: 1.75rem;
      border-block-start: 1px solid var(--border);
      padding-inline: 0.625rem;
      column-gap: 0.5rem;
    }
    .k {
      font: 600 0.5625rem/1.3 var(--font-mono);
      letter-spacing: 0.13em;
      text-transform: uppercase;
      color: var(--muted-foreground);
    }
    .v {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 0.25rem;
      min-inline-size: 0;
      overflow-wrap: anywhere;
    }
    .mono {
      font-family: var(--font-mono);
      font-size: 0.6875rem;
      font-variant-numeric: tabular-nums;
    }
  </style>
</template>;

/** A ruled list line: content left, trailing slot right. */
export const RecLine: TemplateOnlyComponent<{
  Blocks: { default: []; end: [] };
}> = <template>
  <div class='line'>
    <span class='main'>{{yield}}</span>
    {{#if (has-block 'end')}}<span class='end'>{{yield to='end'}}</span>{{/if}}
  </div>
  <style scoped>
    .line {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      min-block-size: 1.75rem;
      padding: 0.25rem 0.625rem;
      border-block-start: 1px solid var(--border);
    }
    .main {
      flex: 1;
      min-inline-size: 0;
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 0.375rem;
    }
    .end {
      flex: none;
    }
  </style>
</template>;

export const RecText: TemplateOnlyComponent<{
  Blocks: { default: [] };
}> = <template>
  <p class='txt'>{{yield}}</p>
  <style scoped>
    .txt {
      margin: 0;
      padding: 0 0.625rem 0.4375rem;
    }
  </style>
</template>;
