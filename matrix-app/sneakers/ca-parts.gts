// Compact layout parts shared by the collection-side sneakers cards
// (collection item, product, completion set, authentication record), so the
// four cards draw one sheet, one ruled key-value list and one atom.
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { Stat } from '@cardstack/pretui/components/stat';
import { realmURL } from '@cardstack/base/card-api';
import { identifyCard } from '@cardstack/runtime-common';

// A small square image, or a muted square when there is no image.
export const CaMark: TemplateOnlyComponent<{
  Args: { src?: string | null; size?: 'sm' | 'md' };
}> = <template>
  <span class='ca-mark' data-size={{if @size @size 'sm'}} aria-hidden='true'>
    {{#if @src}}<img src={{@src}} alt='' />{{/if}}
  </span>
  <style scoped>
    .ca-mark {
      flex: none;
      display: inline-block;
      inline-size: 1.375rem;
      block-size: 1.375rem;
      overflow: hidden;
      border-radius: calc(var(--radius) * 0.6);
      background-color: var(--muted);
    }
    .ca-mark[data-size='sm'] {
      inline-size: 1rem;
      block-size: 1rem;
    }
    .ca-mark[data-size='md'] {
      inline-size: 2rem;
      block-size: 2rem;
      margin-inline-end: var(--boxel-sp-xs);
    }
    img {
      display: block;
      inline-size: 100%;
      block-size: 100%;
      object-fit: cover;
    }
  </style>
</template>;

// The isolated format: header (mark, name, meta, state and actions), a
// stat strip, then main content left and Linked + Details right.
export const CaSheet: TemplateOnlyComponent<{
  Args: { title?: string | null; src?: string | null };
  Blocks: { meta: []; aside: []; stats: []; main: []; side: [] };
}> = <template>
  <article class='ca-sheet'>
    <div class='head'>
      <span class='mark' aria-hidden='true'>
        {{#if @src}}<img src={{@src}} alt='' />{{/if}}
      </span>
      <div class='id'>
        <h1>{{if @title @title 'Untitled'}}</h1>
        <p class='meta'>{{yield to='meta'}}</p>
      </div>
      <div class='aside'>{{yield to='aside'}}</div>
    </div>
    <div class='stats'>{{yield to='stats'}}</div>
    <div class='split'>
      <div class='main'>{{yield to='main'}}</div>
      <aside class='side'>{{yield to='side'}}</aside>
    </div>
  </article>
  <style scoped>
    .ca-sheet {
      container: ca-sheet / inline-size;
      min-block-size: 100%;
      box-sizing: border-box;
      overflow-y: auto;
      background-color: var(--card);
      color: var(--card-foreground);
      font-family: var(--font-sans);
      font-size: 0.75rem;
      line-height: 1.4;
    }
    .head {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--boxel-sp-xs);
      padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
      border-block-end: 1px solid var(--border);
    }
    .mark {
      flex: none;
      inline-size: 1.375rem;
      block-size: 1.375rem;
      overflow: hidden;
      border-radius: calc(var(--radius) * 0.6);
      background-color: var(--muted);
    }
    .mark img {
      display: block;
      inline-size: 100%;
      block-size: 100%;
      object-fit: cover;
    }
    .id {
      flex: 1 1 12rem;
      min-inline-size: 0;
    }
    h1 {
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
      font-weight: 600;
      color: var(--muted-foreground);
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .aside {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--boxel-sp-sm);
    }
    .stats {
      display: grid;
      grid-auto-flow: column;
      grid-auto-columns: minmax(0, 1fr);
      border-block-end: 1px solid var(--border);
    }
    .split {
      display: grid;
      grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
    }
    .side {
      border-inline-start: 1px solid var(--border);
    }
    @container ca-sheet (inline-size < 40rem) {
      .stats {
        grid-auto-flow: row;
      }
      .split {
        grid-template-columns: minmax(0, 1fr);
      }
      .side {
        border-inline-start: none;
        border-block-start: 1px solid var(--border);
      }
    }
  </style>
</template>;

// One tile of the isolated stat strip.
export const CaStat: TemplateOnlyComponent<{
  Args: { label: string; value: string; hint?: string | null };
}> = <template>
  <div class='ca-stat'>
    <Stat
      @label={{@label}}
      @value={{@value}}
      @hint={{if @hint @hint '—'}}
      @roll={{false}}
    />
  </div>
  <style scoped>
    .ca-stat {
      min-inline-size: 0;
      padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
      border-inline-end: 1px solid var(--border);
    }
    .ca-stat:last-child {
      border-inline-end: none;
    }
  </style>
</template>;

// A flat section inside a card: a small bold title over its content, one
// hairline below. `@flush` drops the body padding for a ruled list.
export const CaSection: TemplateOnlyComponent<{
  Args: { title: string; flush?: boolean };
  Blocks: { default: [] };
}> = <template>
  <div class='ca-section'>
    <h2>{{@title}}</h2>
    <div class='body' data-flush={{@flush}}>{{yield}}</div>
  </div>
  <style scoped>
    .ca-section {
      border-block-end: 1px solid var(--border);
    }
    h2 {
      margin: 0;
      padding: var(--boxel-sp-sm) var(--boxel-sp-sm) var(--boxel-sp-xs);
      font-size: 0.8125rem;
      font-weight: 700;
    }
    .body {
      padding: 0 var(--boxel-sp-sm) var(--boxel-sp-sm);
      font-size: 0.75rem;
      line-height: 1.6;
      overflow-wrap: anywhere;
    }
    .body[data-flush] {
      padding: 0;
    }
  </style>
</template>;

// Ruled key-value rows: wrap CaRow items in CaKv.
export const CaKv: TemplateOnlyComponent<{ Blocks: { default: [] } }> =
  <template>
    <dl class='ca-kv'>{{yield}}</dl>
    <style scoped>
      .ca-kv {
        margin: 0;
      }
    </style>
  </template>;

export const CaRow: TemplateOnlyComponent<{
  Args: { label: string };
  Blocks: { default: [] };
}> = <template>
  <div class='ca-row'>
    <dt>{{@label}}</dt>
    <dd>{{yield}}</dd>
  </div>
  <style scoped>
    .ca-row {
      display: grid;
      grid-template-columns: 7.5rem minmax(0, 1fr);
      border-block-start: 1px solid var(--border);
    }
    dt,
    dd {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--boxel-sp-xs);
      min-block-size: 1.75rem;
      margin: 0;
      min-inline-size: 0;
    }
    dt {
      padding-inline-start: var(--boxel-sp-sm);
      font-family: var(--font-mono);
      font-size: 0.5625rem;
      font-weight: 600;
      letter-spacing: 0.13em;
      text-transform: uppercase;
      color: var(--muted-foreground);
    }
    dd {
      padding-inline: var(--boxel-sp-sm);
      font-size: 0.75rem;
    }
  </style>
</template>;

// The embedded format: one header line, then the caller's ruled rows.
export const CaEmbedded: TemplateOnlyComponent<{
  Args: { title?: string | null; src?: string | null };
  Blocks: { meta: []; status: []; default: [] };
}> = <template>
  <article class='ca-emb'>
    <div class='eh'>
      <CaMark @src={{@src}} />
      <div class='id'>
        <h3>{{if @title @title 'Untitled'}}</h3>
        <p class='meta'>{{yield to='meta'}}</p>
      </div>
      <span class='status'>{{yield to='status'}}</span>
    </div>
    {{yield}}
  </article>
  <style scoped>
    .ca-emb {
      background-color: var(--card);
      color: var(--card-foreground);
      font-family: var(--font-sans);
      font-size: 0.75rem;
      line-height: 1.4;
    }
    .eh {
      display: flex;
      align-items: center;
      gap: var(--boxel-sp-xs);
      padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
    }
    .id {
      flex: 1;
      min-inline-size: 0;
    }
    h3,
    .meta {
      margin: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    h3 {
      font-size: 0.8125rem;
      font-weight: 700;
    }
    .meta {
      font-size: 0.6875rem;
      color: var(--muted-foreground);
    }
    .status {
      flex: none;
    }
  </style>
</template>;

// The atom format: mark + name on one line; the name ellipsises first.
export const CaAtom: TemplateOnlyComponent<{
  Args: { title?: string | null; src?: string | null };
}> = <template>
  <span class='ca-atom'>
    <CaMark @src={{@src}} />
    <span class='name'>{{if @title @title 'Untitled'}}</span>
  </span>
  <style scoped>
    .ca-atom {
      display: inline-flex;
      align-items: center;
      gap: var(--boxel-sp-xxs);
      min-inline-size: 0;
      max-inline-size: 100%;
      font-size: 0.6875rem;
      font-weight: 600;
      color: var(--foreground);
    }
    .name {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
  </style>
</template>;

// Short US date, the format every row and stat in these cards uses.
export function caDay(d: Date | null | undefined): string {
  return d
    ? d.toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
      })
    : '—';
}

// Live reverse query for cards in this folder that link to `owner`'s card
// (`path` is the linking field's id path, e.g. 'item.id'). Matched by module
// URL so no card here needs a static import that would close a cycle.
export function caLinkedQuery(
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

export function caInstances(query: { instances?: unknown[] } | undefined) {
  return (query?.instances ?? []).filter(Boolean) as any[];
}
