import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { realmURL } from '@cardstack/runtime-common';

// Academy Desk parts that record-sheet does not have: a live search
// for the cards linking to this one, a ruled list row and a KV list.
import { Kv } from './record-sheet';

/**
 * A live search for the cards of `module`/`name` whose `path` link points at
 * `card`, in `card`'s realm. Called once from a component constructor (the
 * thunks capture their inputs so a later tracked change can't re-run them
 * mid-render). Undefined outside a host that can search.
 */
export function cardsLinkedTo(
  owner: object,
  context: any,
  card: any,
  ref: { module: string; name: string },
  path: string,
): { instances: unknown[]; isLoading: boolean } | undefined {
  let id = card?.id as string | undefined;
  let url = card?.[realmURL];
  let realms = url ? [url.href] : undefined;
  if (!context?.getCards || !id) return undefined;
  let query = { filter: { on: ref, eq: { [path]: id } } };
  let q = context.getCards(
    owner,
    () => query,
    () => realms,
    { isLive: true },
  );
  void q?.instances;
  return q;
}

interface DeskRowSignature {
  Args: { title?: string | null; meta?: string | null };
  Blocks: { default: [] };
  Element: HTMLElement;
}

/** A ruled list row: bold title over a gray meta line, state on the right. */
export const DeskRow: TemplateOnlyComponent<DeskRowSignature> = <template>
  <div class='desk-row' ...attributes>
    <span class='desk-row-t'>
      <strong class='desk-row-title'>{{if @title @title '—'}}</strong>
      {{#if @meta}}<span class='desk-row-meta'>{{@meta}}</span>{{/if}}
    </span>
    {{#if (has-block)}}<span class='desk-row-side'>{{yield}}</span>{{/if}}
  </div>
  <style scoped>
    .desk-row {
      display: flex;
      align-items: center;
      gap: var(--boxel-sp-sm);
      min-block-size: 1.75rem;
      padding: var(--boxel-sp-4xs) var(--boxel-sp-sm);
      border-top: 1px solid var(--border);
      font-size: var(--boxel-font-size-xs);
    }
    .desk-row-t {
      flex: 1;
      min-inline-size: 0;
    }
    .desk-row-title,
    .desk-row-meta {
      display: block;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .desk-row-title {
      font-weight: 700;
    }
    .desk-row-meta {
      font-size: var(--boxel-font-size-2xs);
      color: var(--muted-foreground);
    }
    .desk-row-side {
      flex: none;
    }
  </style>
</template>;

interface KvListSignature {
  Args: { items: { key: string; value?: string | null }[] };
}

/** record-sheet Kv rows from a list; an empty value shows an em dash. */
export const KvList: TemplateOnlyComponent<KvListSignature> = <template>
  {{#each @items as |i|}}
    <Kv @label={{i.key}}>{{if i.value i.value '—'}}</Kv>
  {{/each}}
</template>;
