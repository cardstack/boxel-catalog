// Compact layout parts shared by the marketplace cards (listing, offer,
// member, seller, order): one sheet, stat, section, key-value row and mark,
// so the five cards keep one rhythm.
import GlimmerComponent from '@glimmer/component';
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { DotLabel } from '../hr/dot-enum-field';

type Hue = DotLabel['args']['hue'];

interface SheetSignature {
  Blocks: {
    mark: [];
    title: [];
    meta: [];
    actions: [];
    stats: [];
    main: [];
    side: [];
  };
}

/** The isolated card: header, stat strip, main column and docked side. */
export const CbSheet: TemplateOnlyComponent<SheetSignature> = <template>
  <article class='cb-sheet'>
    <div class='ihead'>
      <div class='who'>
        {{yield to='mark'}}
        <div class='id'>
          <h1 class='name'>{{yield to='title'}}</h1>
          <p class='meta'>{{yield to='meta'}}</p>
        </div>
      </div>
      <div class='bar'>{{yield to='actions'}}</div>
    </div>
    <div class='stats'>{{yield to='stats'}}</div>
    <div class='split'>
      <div class='main'>{{yield to='main'}}</div>
      <aside class='side'>{{yield to='side'}}</aside>
    </div>
  </article>
  <style scoped>
    .cb-sheet {
      container-type: inline-size;
      min-block-size: 100%;
      font-family: var(--font-sans);
      font-size: 0.75rem;
      line-height: 1.4;
      color: var(--card-foreground);
      background-color: var(--card);
      --pretui-button-h: 1.625rem;
      --control-height: 1.625rem;
    }
    .ihead {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      justify-content: space-between;
      gap: var(--boxel-sp-xxs) var(--boxel-sp-xs);
      padding: var(--boxel-sp-xxs) var(--boxel-sp-xs);
    }
    .who {
      display: flex;
      align-items: center;
      gap: var(--boxel-sp-xxs);
      min-inline-size: 0;
    }
    .id {
      min-inline-size: 0;
    }
    .name {
      margin: 0;
      font-family: var(--font-sans);
      font-size: 0.8125rem;
      font-weight: 700;
      letter-spacing: normal;
      text-transform: none;
    }
    .meta {
      margin: 0;
      font-size: 0.6875rem;
      color: var(--muted-foreground);
    }
    .bar {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--boxel-sp-xxs) var(--boxel-sp-xs);
    }
    .stats {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(9rem, 1fr));
      border-block-start: 1px solid var(--border);
      overflow: hidden;
    }
    .split {
      display: grid;
      grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
      border-block-start: 1px solid var(--border);
    }
    .side {
      border-inline-start: 1px solid var(--border);
    }
    @container (width < 40rem) {
      .split {
        grid-template-columns: minmax(0, 1fr);
      }
      .side {
        border-inline-start: 0;
        border-block-start: 1px solid var(--border);
      }
    }
  </style>
</template>;

interface StatSignature {
  Args: {
    label: string;
    value?: string | number | null;
    meta?: string;
    hue?: Hue;
  };
}

/** One tile of the stat strip: dot + mono caps label, big value, grey line. */
export const CbStat: TemplateOnlyComponent<StatSignature> = <template>
  <div class='stat'>
    <span class='cap'><DotLabel @hue={{@hue}} />{{@label}}</span>
    <span class='num'>{{if @value @value '—'}}</span>
    <span class='meta'>{{if @meta @meta '—'}}</span>
  </div>
  <style scoped>
    .stat {
      display: flex;
      flex-direction: column;
      gap: var(--boxel-sp-6xs);
      min-inline-size: 0;
      padding: var(--boxel-sp-xxs) var(--boxel-sp-xs);
      border-inline-end: 1px solid var(--border);
      border-block-end: 1px solid var(--border);
      margin-block-end: -1px;
    }
    .cap {
      display: inline-flex;
      align-items: center;
      gap: var(--boxel-sp-5xs);
      font-family: var(--font-mono);
      font-weight: 600;
      font-size: 0.5625rem;
      letter-spacing: 0.13em;
      text-transform: uppercase;
      color: var(--muted-foreground);
    }
    .num {
      font-size: 1.375rem;
      font-weight: 700;
      line-height: 1.15;
      font-variant-numeric: tabular-nums;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .meta {
      font-size: 0.6875rem;
      color: var(--muted-foreground);
    }
  </style>
</template>;

interface SectionSignature {
  Args: { title: string; text?: string | null };
  Blocks: { default: [] };
}

/** A flat ruled section: small bold title, then key-value rows or a note. */
export const CbSection: TemplateOnlyComponent<SectionSignature> = <template>
  <div class='blk'>
    <h2>{{@title}}</h2>
    {{#if (has-block)}}
      <dl class='kv'>{{yield}}</dl>
    {{else}}
      <p class='txt'>{{if @text @text '—'}}</p>
    {{/if}}
  </div>
  <style scoped>
    .blk + .blk {
      border-block-start: 1px solid var(--border);
    }
    h2 {
      margin: 0;
      padding: var(--boxel-sp-xs) var(--boxel-sp-xs) var(--boxel-sp-xxs);
      font-family: var(--font-sans);
      font-size: 0.8125rem;
      font-weight: 700;
      letter-spacing: normal;
      text-transform: none;
    }
    .kv {
      display: grid;
      grid-template-columns: minmax(6rem, 9.5rem) minmax(0, 1fr);
      margin: 0;
    }
    .txt {
      margin: 0;
      padding: var(--boxel-sp-xxs) var(--boxel-sp-xs) var(--boxel-sp-xs);
      border-block-start: 1px solid var(--border);
      white-space: pre-line;
    }
  </style>
</template>;

interface KvSignature {
  Blocks: { default: [] };
}

/** Ruled key-value rows outside a section (embedded format). */
export const CbKv: TemplateOnlyComponent<KvSignature> = <template>
  <dl class='kv'>{{yield}}</dl>
  <style scoped>
    .kv {
      display: grid;
      grid-template-columns: 6.5rem minmax(0, 1fr);
      margin: 0;
    }
  </style>
</template>;

interface RowSignature {
  Args: {
    label: string;
    value?: string | number | null;
    hue?: Hue;
    state?: string;
  };
  Blocks: { default: [] };
}

/** One ruled row: mono caps label, value (or yielded atom), optional dot. */
export const CbRow: TemplateOnlyComponent<RowSignature> = <template>
  <dt class='k'>{{@label}}</dt>
  <dd class='v'>
    {{#if (has-block)}}
      {{yield}}
    {{else}}
      <span class='val'>{{if @value @value '—'}}</span>
    {{/if}}
    {{#if @state}}<DotLabel @hue={{@hue}} @label={{@state}} />{{/if}}
  </dd>
  <style scoped>
    .k,
    .v {
      display: flex;
      align-items: center;
      min-block-size: 1.75rem;
      margin: 0;
      border-block-start: 1px solid var(--border);
    }
    .k {
      padding: var(--boxel-sp-6xs) var(--boxel-sp-xs);
      font-family: var(--font-mono);
      font-size: 0.5625rem;
      font-weight: 600;
      letter-spacing: 0.13em;
      text-transform: uppercase;
      color: var(--muted-foreground);
    }
    .v {
      flex-wrap: wrap;
      gap: var(--boxel-sp-5xs) var(--boxel-sp-xxs);
      min-inline-size: 0;
      padding: var(--boxel-sp-6xs) var(--boxel-sp-xs);
    }
    .val {
      min-inline-size: 0;
      overflow-wrap: anywhere;
    }
  </style>
</template>;

interface EmbeddedSignature {
  Blocks: { mark: []; title: []; meta: []; status: []; default: [] };
}

/** The embedded format: mark + name + status line, then ruled rows. */
export const CbEmbedded: TemplateOnlyComponent<EmbeddedSignature> = <template>
  <article class='emb'>
    <div class='eh'>
      {{yield to='mark'}}
      <div class='id'>
        <h3>{{yield to='title'}}</h3>
        <p class='meta'>{{yield to='meta'}}</p>
      </div>
      <span class='st'>{{yield to='status'}}</span>
    </div>
    {{yield}}
  </article>
  <style scoped>
    .emb {
      font-family: var(--font-sans);
      font-size: 0.75rem;
      line-height: 1.4;
      color: var(--card-foreground);
      background-color: var(--card);
    }
    .eh {
      display: flex;
      align-items: center;
      gap: var(--boxel-sp-xxs);
      padding: var(--boxel-sp-xxs) var(--boxel-sp-xs);
    }
    .id {
      flex: 1;
      min-inline-size: 0;
    }
    h3 {
      margin: 0;
      font-size: 0.8125rem;
      font-weight: 700;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .meta {
      margin: 0;
      font-size: 0.6875rem;
      color: var(--muted-foreground);
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .st {
      flex: none;
    }
  </style>
</template>;

interface MarkSignature {
  Args: { src?: string | null; text?: string; size?: 'sm' | 'md' | 'lg' };
}

/** A square type mark: the item photo when there is one, else two letters. */
export class CbMark extends GlimmerComponent<MarkSignature> {
  <template>
    <span class='mark' data-size={{if @size @size 'md'}} aria-hidden='true'>
      {{#if @src}}
        <img src={{@src}} alt='' />
      {{else}}
        {{@text}}
      {{/if}}
    </span>
    <style scoped>
      .mark {
        flex: none;
        display: inline-grid;
        place-items: center;
        inline-size: 1.375rem;
        block-size: 1.375rem;
        overflow: hidden;
        border-radius: calc(var(--radius) * 0.6);
        background-color: var(--muted);
        font-family: var(--font-mono);
        font-size: 0.5625rem;
        font-weight: 700;
        color: var(--foreground);
      }
      .mark[data-size='sm'] {
        inline-size: 1rem;
        block-size: 1rem;
        font-size: 0.5rem;
      }
      .mark[data-size='lg'] {
        inline-size: 2rem;
        block-size: 2rem;
        font-size: 0.6875rem;
      }
      img {
        inline-size: 100%;
        block-size: 100%;
        object-fit: cover;
      }
    </style>
  </template>
}

interface AtomSignature {
  Blocks: { mark: []; default: [] };
}

/** The atom format: mark + name on one line; the name ellipsises first. */
export const CbAtom: TemplateOnlyComponent<AtomSignature> = <template>
  <span class='atom'>
    {{yield to='mark'}}
    <span class='n'>{{yield}}</span>
  </span>
  <style scoped>
    .atom {
      display: inline-flex;
      align-items: center;
      gap: var(--boxel-sp-5xs);
      min-inline-size: 0;
      max-inline-size: 100%;
      font-size: 0.6875rem;
      font-weight: 600;
      color: var(--foreground);
    }
    .n {
      min-inline-size: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
  </style>
</template>;

/** "Aug 18, 2026" (long) or "Aug 18" (short) for a calendar date. */
export function day(d: Date | null | undefined, short = false): string {
  if (!d) {
    return '';
  }
  return d.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    ...(short ? {} : { year: 'numeric' }),
    timeZone: 'UTC',
  });
}
