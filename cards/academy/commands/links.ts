import { realmURL, type CardDef } from '@cardstack/base/card-api';
import type { CommandContext } from '@cardstack/runtime-common';

import { getCard } from '@cardstack/catalog/utils/find-card';
import { linkedId, linkedIds } from '@cardstack/catalog/utils/linked-id';

// A command runs outside a render, so a fetched card's links may not have
// loaded. These follow a link by its stored id and fetch the target.

/** The card a `linksTo` on `card` points at, fetched; undefined when unset. */
export async function linkedCard<T extends CardDef>(
  commandContext: CommandContext,
  card: CardDef,
  fieldName: string,
): Promise<T | undefined> {
  let id = linkedId(card, fieldName);
  return id ? getCard<T>(commandContext, id) : undefined;
}

/** The cards a `linksToMany` on `card` points at, fetched, in order. */
export async function linkedCards<T extends CardDef>(
  commandContext: CommandContext,
  card: CardDef,
  fieldName: string,
): Promise<T[]> {
  let cards = await Promise.all(
    linkedIds(card, fieldName).map((id) => getCard<T>(commandContext, id)),
  );
  return cards.filter(Boolean);
}

/** The realm a card lives in. */
export function realmOf(card: CardDef | undefined): string | undefined {
  return (card as any)?.[realmURL]?.href;
}

/**
 * One list per id from several sources. A realm search can miss a card that
 * isn't indexed yet, so a caller's already-loaded cards are kept alongside it.
 */
export function byId<T extends CardDef>(...lists: (T[] | undefined)[]): T[] {
  let seen = new Map<string, T>();
  for (let list of lists) {
    for (let card of list ?? []) {
      if (card?.id && !seen.has(card.id)) {
        seen.set(card.id, card);
      }
    }
  }
  return [...seen.values()];
}
