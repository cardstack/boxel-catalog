import type { CardDef } from '@cardstack/base/card-api';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import { SearchCardsByQueryCommand } from '@cardstack/boxel-host/commands/search-cards';
import { identifyCard, type CommandContext } from '@cardstack/runtime-common';

import { linkedId } from './linked-id';

/** Fetch a card by id through the host, so its own fields are loaded. */
export async function getCard<T extends CardDef>(
  commandContext: CommandContext,
  id: string,
): Promise<T> {
  return (await new GetCardCommand(commandContext).execute({
    cardId: id,
  })) as T;
}

/**
 * A command input's linked card, fetched. The link may arrive as a bare
 * reference that reads `undefined` until loaded, so the id is taken from the
 * relationship; an inline card with no id yet is returned as it is.
 */
export async function inputCard<T extends CardDef>(
  commandContext: CommandContext,
  input: CardDef,
  fieldName: string,
): Promise<T | undefined> {
  let id = linkedId(input, fieldName);
  if (id) {
    return getCard<T>(commandContext, id);
  }
  return (input as any)[fieldName] as T | undefined;
}

// The search covers every realm the user has added, so hits are kept only
// when they sit in `realm`.
async function search(
  commandContext: CommandContext,
  type: typeof CardDef,
  match: Record<string, string | null | undefined>,
  realm: string,
): Promise<string[]> {
  let ref = identifyCard(type);
  if (!ref) {
    return [];
  }
  let eq = Object.fromEntries(
    Object.entries(match).map(([k, v]) => [k, v ?? null]),
  );
  let result = await new SearchCardsByQueryCommand(commandContext).execute({
    query: { filter: { on: ref, eq } },
  } as any);
  let root = realm.endsWith('/') ? realm : `${realm}/`;
  return ((result?.cardIds ?? []) as string[]).filter((id) =>
    id.startsWith(root),
  );
}

/**
 * The first saved card of `type` in `realm` whose fields equal `match`, or
 * undefined. A command uses it to find what an earlier, interrupted run
 * already wrote. A search can miss a card that isn't indexed yet, so this
 * only ever adds to what a command knows, never replaces it.
 */
export async function findCard<T extends CardDef>(
  commandContext: CommandContext,
  type: typeof CardDef,
  match: Record<string, string | null | undefined>,
  realm: string,
): Promise<T | undefined> {
  let [id] = await search(commandContext, type, match, realm);
  return id ? getCard<T>(commandContext, id) : undefined;
}

/** Every saved card of `type` in `realm` whose fields equal `match`. */
export async function findCards<T extends CardDef>(
  commandContext: CommandContext,
  type: typeof CardDef,
  match: Record<string, string | null | undefined>,
  realm: string,
): Promise<T[]> {
  let ids = await search(commandContext, type, match, realm);
  return Promise.all(ids.map((id) => getCard<T>(commandContext, id)));
}
