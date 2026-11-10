// Compact layout parts shared by every sneakers card: one sheet, stat,
// section, key-value row, mark, embedded header and atom, so the cards keep
// one rhythm. A sheet, embedded header or atom draws its own mark and title
// from `@src` and `@title`, or takes `mark` / `title` blocks instead.
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { Stat } from '@cardstack/pretui/components/stat';
import { realmURL } from '@cardstack/base/card-api';
import { identifyCard } from '@cardstack/runtime-common';
import { DotLabel } from '../hr/dot-enum-field';

type Hue = DotLabel['args']['hue'];
type Tone = 'neutral' | 'info' | 'success' | 'warning' | 'danger' | 'attention';

// Stat takes Pret UI tones; the cards speak in DotLabel hues.
const HUE_TONE: Record<string, Tone> = {
  green: 'success',
  teal: 'success',
  blue: 'info',
  amber: 'warning',
  orange: 'warning',
  red: 'danger',
  purple: 'attention',
  slate: 'neutral',
};
const toneOf = (hue: Hue | undefined) => (hue ? HUE_TONE[hue] : undefined);

// Zero is a value; only a missing one shows the dash.
const shown = (v: string | number | null | undefined) =>
  v === null || v === undefined || v === '' ? '—' : v;

interface MarkSignature {
  Args: { src?: string | null; text?: string; size?: 'sm' | 'md' | 'lg' };
}

/** A square type mark: the photo when there is one, else up to two letters. */
export const SnMark: TemplateOnlyComponent<MarkSignature> = <template>
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
      color: var(--foreground);
      font-family: var(--font-mono);
      font-size: 0.5625rem;
      font-weight: 700;
    }
    .mark[data-size='sm'] {
      inline-size: 1rem;
      block-size: 1rem;
      font-size: 0.5rem;
    }
    .mark[data-size='lg'] {
      inline-size: 2rem;
      block-size: 2rem;
      font-size: var(--boxel-font-size-2xs);
    }
    img {
      inline-size: 100%;
      block-size: 100%;
      object-fit: cover;
    }
  </style>
</template>;

interface SheetSignature {
  Args: { title?: string | null; src?: string | null };
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
export const SnSheet: TemplateOnlyComponent<SheetSignature> = <template>
  <article class='sn-sheet'>
    <div class='ihead'>
      <div class='who'>
        {{#if (has-block 'mark')}}
          {{yield to='mark'}}
        {{else}}
          <SnMark @src={{@src}} />
        {{/if}}
        <div class='id'>
          <h1 class='name'>{{#if (has-block 'title')}}{{yield
                to='title'
              }}{{else}}{{if @title @title 'Untitled'}}{{/if}}</h1>
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
    .sn-sheet {
      container-type: inline-size;
      min-block-size: 100%;
      font-family: var(--font-sans);
      font-size: var(--boxel-font-size-xs);
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
      gap: var(--boxel-sp-2xs) var(--boxel-sp-xs);
      padding: var(--boxel-sp-2xs) var(--boxel-sp-xs);
    }
    .who {
      display: flex;
      align-items: center;
      gap: var(--boxel-sp-2xs);
      min-inline-size: 0;
    }
    .id {
      min-inline-size: 0;
    }
    .name {
      font-family: var(--font-sans);
      font-size: var(--boxel-font-size-sm);
      font-weight: 700;
      letter-spacing: normal;
      text-transform: none;
      overflow-wrap: break-word;
    }
    .meta {
      font-size: var(--boxel-font-size-2xs);
      color: var(--muted-foreground);
    }
    .bar {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--boxel-sp-2xs) var(--boxel-sp-xs);
    }
    .stats {
      --text-stat: var(--boxel-font-size-lg);
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
    hint?: string | null;
    hue?: Hue;
  };
}

/** One tile of the stat strip; the strip clips each tile's overhanging rule. */
export const SnStat: TemplateOnlyComponent<StatSignature> = <template>
  <div class='stat'>
    <Stat
      @label={{@label}}
      @value={{shown @value}}
      @hint={{if @hint @hint '—'}}
      @tone={{toneOf @hue}}
      @roll={{false}}
    />
  </div>
  <style scoped>
    .stat {
      min-inline-size: 0;
      padding: var(--boxel-sp-2xs) var(--boxel-sp-xs);
      border-inline-end: 1px solid var(--border);
      border-block-end: 1px solid var(--border);
      margin-block-end: -1px;
    }
  </style>
</template>;

interface SectionSignature {
  Args: { title: string; text?: string | null; flush?: boolean };
  Blocks: { default: [] };
}

/** A flat ruled section: small bold title over its content, or over `@text`.
    `@flush` drops the body padding for a ruled list. */
export const SnSection: TemplateOnlyComponent<SectionSignature> = <template>
  <div class='blk'>
    <h2>{{@title}}</h2>
    {{#if (has-block)}}
      <div class='body' data-flush={{@flush}}>{{yield}}</div>
    {{else}}
      <p class='txt'>{{if @text @text '—'}}</p>
    {{/if}}
  </div>
  <style scoped>
    .blk + .blk {
      border-block-start: 1px solid var(--border);
    }
    h2 {
      padding: var(--boxel-sp-xs) var(--boxel-sp-xs) var(--boxel-sp-2xs);
      font-family: var(--font-sans);
      font-size: var(--boxel-font-size-sm);
      font-weight: 700;
      letter-spacing: normal;
      text-transform: none;
    }
    .body {
      padding: 0 var(--boxel-sp-xs) var(--boxel-sp-xs);
      line-height: 1.6;
      overflow-wrap: break-word;
    }
    .body[data-flush] {
      padding: 0;
    }
    .txt {
      padding: var(--boxel-sp-2xs) var(--boxel-sp-xs) var(--boxel-sp-xs);
      border-block-start: 1px solid var(--border);
      white-space: pre-line;
    }
  </style>
</template>;

/** Ruled key-value rows: wrap SnRow items in SnKv. */
export const SnKv: TemplateOnlyComponent<{ Blocks: { default: [] } }> =
  <template>
    <dl class='kv'>{{yield}}</dl>
    <style scoped>
      .kv {
        display: grid;
        grid-template-columns: minmax(6rem, 9.5rem) minmax(0, 1fr);
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

/** One ruled row: mono caps label, value (or yielded content), optional dot. */
export const SnRow: TemplateOnlyComponent<RowSignature> = <template>
  <dt class='k'>{{@label}}</dt>
  <dd class='v'>
    {{#if (has-block)}}
      {{yield}}
    {{else}}
      <span class='val'>{{shown @value}}</span>
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
      gap: var(--boxel-sp-5xs) var(--boxel-sp-2xs);
      min-inline-size: 0;
      padding: var(--boxel-sp-6xs) var(--boxel-sp-xs);
    }
    .val {
      min-inline-size: 0;
      overflow-wrap: break-word;
    }
  </style>
</template>;

interface EmbeddedSignature {
  Args: { title?: string | null; src?: string | null };
  Blocks: { mark: []; title: []; meta: []; status: []; default: [] };
}

/** The embedded format: mark + name + status line, then ruled rows. */
export const SnEmbedded: TemplateOnlyComponent<EmbeddedSignature> = <template>
  <article class='emb'>
    <div class='eh'>
      {{#if (has-block 'mark')}}
        {{yield to='mark'}}
      {{else}}
        <SnMark @src={{@src}} @size='sm' />
      {{/if}}
      <div class='id'>
        <h3>{{#if (has-block 'title')}}{{yield to='title'}}{{else}}{{if
              @title
              @title
              'Untitled'
            }}{{/if}}</h3>
        <p class='meta'>{{yield to='meta'}}</p>
      </div>
      <span class='st'>{{yield to='status'}}</span>
    </div>
    {{yield}}
  </article>
  <style scoped>
    .emb {
      font-family: var(--font-sans);
      font-size: var(--boxel-font-size-xs);
      line-height: 1.4;
      color: var(--card-foreground);
      background-color: var(--card);
    }
    .eh {
      display: flex;
      align-items: center;
      gap: var(--boxel-sp-2xs);
      padding: var(--boxel-sp-2xs) var(--boxel-sp-xs);
    }
    .id {
      flex: 1;
      min-inline-size: 0;
    }
    h3,
    .meta {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    h3 {
      font-size: var(--boxel-font-size-sm);
      font-weight: 700;
    }
    .meta {
      font-size: var(--boxel-font-size-2xs);
      color: var(--muted-foreground);
    }
    .st {
      flex: none;
    }
  </style>
</template>;

interface AtomSignature {
  Args: { title?: string | null; src?: string | null };
  Blocks: { mark: []; default: [] };
}

/** The atom format: mark + name on one line; the name ellipsises first. */
export const SnAtom: TemplateOnlyComponent<AtomSignature> = <template>
  <span class='atom'>
    {{#if (has-block 'mark')}}
      {{yield to='mark'}}
    {{else}}
      <SnMark @src={{@src}} @size='sm' />
    {{/if}}
    <span class='n'>{{#if (has-block)}}{{yield}}{{else}}{{if
          @title
          @title
          'Untitled'
        }}{{/if}}</span>
  </span>
  <style scoped>
    .atom {
      display: inline-flex;
      align-items: center;
      gap: var(--boxel-sp-5xs);
      min-inline-size: 0;
      max-inline-size: 100%;
      font-size: var(--boxel-font-size-2xs);
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

/** "Aug 18, 2026" (long) or "Aug 18" (short). DateField values are local
    midnights, so the date is read in local time. */
export function day(d: Date | null | undefined, short = false): string {
  if (!d) {
    return '';
  }
  return d.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    ...(short ? {} : { year: 'numeric' }),
  });
}

// Live reverse query for cards in this folder that link to `owner`'s card
// (`path` is the linking field's id path, e.g. 'item.id'). Matched by module
// URL so no card here needs a static import that would close a cycle.
export function linkedQuery(
  owner: {
    args: { model?: any; context?: any };
  },
  name: string,
  module: string,
  path: string,
) {
  return owner.args.context?.getCards(
    owner,
    () => {
      let id = owner.args.model?.id;
      if (!id) {
        return undefined;
      }
      // Resolve the sibling module against the owner card's own module URL.
      let own = identifyCard(owner.args.model.constructor) as
        | { module: string }
        | undefined;
      if (!own) {
        return undefined;
      }
      let on = { module: new URL(module, own.module).href, name };
      return { filter: { on, eq: { [path]: id } } };
    },
    () => {
      let realm = owner.args.model?.[realmURL];
      return realm ? [realm.href] : [];
    },
    { isLive: true },
  );
}

export function instances(query: { instances?: unknown[] } | undefined) {
  return (query?.instances ?? []).filter(Boolean) as any[];
}
