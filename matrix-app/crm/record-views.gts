// Compact record layouts shared by the five CRM cards' isolated + embedded
// formats: mark + title + status chips, an optional stat strip, ruled key-value rows.
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { Chip } from '@cardstack/pretui/components/chip';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';
import { Stat } from '@cardstack/pretui/components/stat';
import { realmURL } from '@cardstack/runtime-common';

export interface RecordChip {
  label: string;
  hue?: string;
}
export interface RecordStat {
  label: string;
  value: string | number;
  hint?: string;
  tone?: string;
  currency?: string;
}

interface HeaderArgs {
  mark: string;
  title: string;
  subtitle?: string;
  chips?: RecordChip[];
}

const Header: TemplateOnlyComponent<{
  Args: HeaderArgs;
  Blocks: { actions: [] };
}> = <template>
  <header class='rv-head'>
    <Avatar @name={{@mark}} @shape='rounded' @size={{24}} />
    <div class='rv-id'>
      <strong class='rv-title'>{{@title}}</strong>
      {{#if @subtitle}}<span class='rv-sub'>{{@subtitle}}</span>{{/if}}
    </div>
    <div class='rv-chips'>
      {{#each @chips as |c|}}
        <Chip @appearance='plain' @hue={{c.hue}} @label={{c.label}} />
      {{/each}}
    </div>
    {{#if (has-block 'actions')}}
      <div class='rv-acts'>{{yield to='actions'}}</div>
    {{/if}}
  </header>
  <style scoped>
    .rv-head {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      padding: 0.5rem 0.625rem;
      min-inline-size: 0;
    }
    .rv-id {
      display: flex;
      flex-direction: column;
      min-inline-size: 0;
      flex: 1;
    }
    .rv-title {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .rv-sub {
      font-size: 0.6875rem;
      color: var(--muted-foreground);
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .rv-acts {
      display: flex;
      gap: 0.375rem;
      flex-shrink: 0;
    }
    .rv-chips {
      display: flex;
      gap: 0.5rem;
      flex-shrink: 0;
    }
  </style>
</template>;

interface EmbeddedArgs extends HeaderArgs {
  summary?: string;
  items: KeyValueItem[];
}

export const RecordEmbedded: TemplateOnlyComponent<{
  Args: EmbeddedArgs;
  Blocks: { value: [KeyValueItem] };
}> = <template>
  <article class='rv-embedded'>
    <Header
      @mark={{@mark}}
      @title={{@title}}
      @subtitle={{@subtitle}}
      @chips={{@chips}}
    />
    {{#if @summary}}<p class='rv-summary'>{{@summary}}</p>{{/if}}
    <KeyValue
      @items={{@items}}
      @labelStyle='eyebrow'
      @divided={{true}}
      class='rv-kv'
    >
      <:value as |row|>{{yield row to='value'}}</:value>
    </KeyValue>
  </article>
  <style scoped>
    .rv-embedded {
      font-size: 0.75rem;
      line-height: 1.4;
      --text-stat: 1.375rem;
      --text-ui-xs: 0.6875rem;
      --boxel-sp-xs: 0.35rem;
      --boxel-sp-lg: 0.75rem;
      --pretui-kv-label-font-size: 0.5625rem;
      --pretui-kv-label-color: var(--muted-foreground);
      border: 1px solid var(--border);
      border-radius: var(--radius);
      overflow: hidden;
      color: var(--card-foreground);
    }
    .rv-summary {
      margin: 0;
      padding: 0 0.625rem 0.375rem;
      font-size: 0.6875rem;
      color: var(--muted-foreground);
    }
    .rv-kv {
      border-block-start: 1px solid var(--border);
      padding-inline: 0.625rem;
      padding-block-end: 0.4375rem;
      --pretui-kv-label-size: 0.5625rem;
    }
  </style>
</template>;

interface PageArgs extends HeaderArgs {
  stats?: RecordStat[];
  /** a first side section ("Contact": email, phone) above Linked */
  lead?: { title: string; items: KeyValueItem[] };
  linked?: KeyValueItem[];
  details: KeyValueItem[];
}

export const RecordPage: TemplateOnlyComponent<{
  Args: PageArgs;
  Blocks: { main: []; value: [KeyValueItem]; actions: [] };
}> = <template>
  <article class='rv-page'>
    {{#if (has-block 'actions')}}
      <Header
        @mark={{@mark}}
        @title={{@title}}
        @subtitle={{@subtitle}}
        @chips={{@chips}}
      ><:actions>{{yield to='actions'}}</:actions></Header>
    {{else}}
      <Header
        @mark={{@mark}}
        @title={{@title}}
        @subtitle={{@subtitle}}
        @chips={{@chips}}
      />
    {{/if}}
    {{#if @stats}}
      <div class='rv-stats'>
        {{#each @stats as |s|}}
          <div class='rv-stat'><Stat
              @label={{s.label}}
              @value={{s.value}}
              @tone={{s.tone}}
              @hint={{s.hint}}
              @style={{if s.currency 'currency'}}
              @currency={{s.currency}}
              @maximumFractionDigits={{0}}
              @roll={{false}}
            /></div>
        {{/each}}
      </div>
    {{/if}}
    <div class='rv-cols'>
      {{#if (has-block 'main')}}<div class='rv-main'>{{yield
            to='main'
          }}</div>{{/if}}
      <div class='rv-side' data-solo={{unless (has-block 'main') 'true'}}>
        {{#if @lead}}
          <h2 class='rv-h'>{{@lead.title}}</h2>
          <KeyValue
            @items={{@lead.items}}
            @labelStyle='eyebrow'
            @divided={{true}}
            class='rv-kv'
          >
            <:value as |row|>{{yield row to='value'}}</:value>
          </KeyValue>
        {{/if}}
        {{#if @linked}}
          <h2 class='rv-h'>Linked</h2>
          <KeyValue
            @items={{@linked}}
            @labelStyle='eyebrow'
            @divided={{true}}
            class='rv-kv'
          >
            <:value as |row|>{{yield row to='value'}}</:value>
          </KeyValue>
        {{/if}}
        <h2 class='rv-h'>Details</h2>
        <KeyValue
          @items={{@details}}
          @labelStyle='eyebrow'
          @divided={{true}}
          class='rv-kv'
        >
          <:value as |row|>{{yield row to='value'}}</:value>
        </KeyValue>
      </div>
    </div>
  </article>
  <style scoped>
    .rv-page {
      font-size: 0.75rem;
      line-height: 1.4;
      --text-stat: 1.375rem;
      --text-ui-xs: 0.6875rem;
      --boxel-sp-xs: 0.35rem;
      --boxel-sp-lg: 0.75rem;
      --pretui-kv-label-font-size: 0.5625rem;
      --pretui-kv-label-color: var(--muted-foreground);
      max-inline-size: 64rem;
      margin: 0 auto;
      border: 1px solid var(--border);
      border-radius: var(--radius);
      background: var(--card);
      color: var(--card-foreground);
      overflow: hidden;
    }
    .rv-stats {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(10rem, 1fr));
      border-block: 1px solid var(--border);
    }
    .rv-stat {
      padding: 0.5rem 0.625rem;
      border-inline-end: 1px solid var(--border);
    }
    .rv-cols {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(18rem, 1fr));
    }
    .rv-cols > * {
      min-inline-size: 0;
    }
    .rv-main > :not(section):not(h2):not(div) {
      margin: 0.4375rem 0.625rem;
    }
    .rv-side {
      border-inline-start: 1px solid var(--border);
      padding-block-end: 0.4375rem;
    }
    .rv-side[data-solo] {
      border-inline-start: 0;
      grid-column: 1 / -1;
    }
    .rv-h {
      margin: 0;
      padding: 0.5rem 0.625rem;
      font-size: 0.75rem;
      font-weight: 700;
      border-block-end: 1px solid var(--border);
    }
    .rv-kv {
      padding-inline: 0.625rem;
      --pretui-kv-label-size: 0.5625rem;
    }
  </style>
</template>;

/** "Sep 30" / "Sep 30, 2026" from a Date or ISO string; '' when unset or invalid. */
export function shortDate(d: Date | string | null | undefined, year = false) {
  let date = d ? new Date(d) : undefined;
  return date && !isNaN(+date)
    ? date.toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        year: year ? 'numeric' : undefined,
      })
    : '';
}

/** Whole-dollar money, "$24,000". */
export function usd(amount: number | undefined, code = 'USD') {
  return typeof amount === 'number'
    ? new Intl.NumberFormat('en-US', {
        style: 'currency',
        currency: code,
        maximumFractionDigits: 0,
      }).format(amount)
    : '';
}

// Cards that point at a record (deals of an account, activity about a deal).
// Built once in the isolated view's constructor: a search created at the top of
// the card, not inside a nested list, and with one stable realms array, so the
// search never re-aims mid-render. Types are matched by module URL, so the
// owning card needs no import of the card that points at it (no import cycle).
export function relatedSearch(
  owner: object,
  context: any,
  model: () => any,
  module: string,
  name: string,
  path: string,
) {
  let realmsCache: { href: string; list: string[] } | undefined;
  let realms = () => {
    let href = model()?.[realmURL]?.href as string | undefined;
    if (!href) return undefined;
    if (realmsCache?.href !== href) realmsCache = { href, list: [href] };
    return realmsCache.list;
  };
  return context?.getCards(
    owner,
    () => {
      let id = model()?.id;
      return id
        ? {
            filter: {
              on: { module, name },
              eq: { [path]: id },
            },
          }
        : undefined;
    },
    realms,
    { isLive: true },
  );
}

interface RelatedArgs {
  title?: string;
  cards: readonly any[] | undefined;
  empty: string;
  /** grey meta after the atom ("Proposal · closes Jul 20") */
  meta?: (card: any) => string | undefined;
  /** right side: status dot + text, then a mono amount */
  status?: (card: any) => string | undefined;
  amount?: (card: any) => string | undefined;
}

/** A titled block of one-line rows: each linked card as its bare atom. */
export const RelatedList: TemplateOnlyComponent<{ Args: RelatedArgs }> =
  <template>
    <section class='rl'>
      {{#if @title}}<h2 class='rl-h'>{{@title}}</h2>{{/if}}
      {{#each @cards as |card|}}
        <div class='rl-row'>
          <span class='rl-atom'>{{#let (atomOf card) as |A|}}<A
                @format='atom'
                @displayContainer={{false}}
              />{{/let}}</span>
          {{#if @meta}}<span class='rl-meta'>{{call @meta card}}</span>{{/if}}
          <span class='rl-end'>
            {{#if @status}}{{#let (call @status card) as |st|}}{{#if st}}<Chip
                    @appearance='plain'
                    @label={{st}}
                  />{{/if}}{{/let}}{{/if}}
            {{#if @amount}}<span class='rl-amt'>{{call
                  @amount
                  card
                }}</span>{{/if}}
          </span>
        </div>
      {{else}}
        <p class='rl-empty'>{{@empty}}</p>
      {{/each}}
    </section>
    <style scoped>
      .rl-h {
        margin: 0;
        padding: 0.4375rem 0.625rem;
        font-size: 0.75rem;
        font-weight: 700;
        border-block-end: 1px solid var(--border);
      }
      .rl-row {
        display: flex;
        align-items: center;
        min-block-size: 1.75rem;
        padding-inline: 0.625rem;
        font-size: 0.75rem;
        min-inline-size: 0;
      }
      .rl-atom {
        display: inline-flex;
        align-items: center;
        flex: 0 1 auto;
        min-inline-size: min(10rem, 60%);
        overflow: hidden;
      }
      .rl-meta {
        flex: 1 1 0;
        margin-inline-start: 0.5rem;
        font-size: 0.6875rem;
        color: var(--muted-foreground);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        min-inline-size: 0;
      }
      .rl-end {
        margin-inline-start: auto;
        display: inline-flex;
        align-items: center;
        gap: 0.75rem;
        flex-shrink: 0;
        padding-inline-start: 0.5rem;
      }
      .rl-amt {
        font-family: var(--font-mono);
        font-size: 0.6875rem;
        font-variant-numeric: tabular-nums;
      }
      .rl-row + .rl-row {
        border-block-start: 1px solid var(--border);
      }
      .rl-empty {
        margin: 0;
        padding: 0.4375rem 0.625rem;
        font-size: 0.6875rem;
        color: var(--muted-foreground);
      }
    </style>
  </template>;

function atomOf(card: any) {
  return card?.constructor?.getComponent?.(card);
}

function call(fn: (x: any) => any, x: any) {
  return fn(x);
}

/** Open a new card in edit format, linked to `model` through `link`. */
export async function createLinked(
  args: any,
  module: string,
  name: string,
  link: string,
  attributes: Record<string, unknown> = {},
) {
  let model = args.model;
  let realm = model?.[realmURL];
  if (!model?.id) return;
  let ref = { module, name };
  await args.createCard?.(ref, undefined, {
    realmURL: realm ? new URL(realm.href) : undefined,
    doc: {
      data: {
        attributes,
        relationships: { [link]: { links: { self: model.id } } },
        meta: { adoptsFrom: ref },
      },
    },
  });
}

/** The realm href a card lives in, for commands that write next to it. */
export function relatedRealm(model: any): string | undefined {
  return model?.[realmURL]?.href;
}
