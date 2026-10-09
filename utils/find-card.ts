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

/**
 * The first saved card of `type` whose fields equal `match`, or undefined.
 * A command uses it to find what an earlier, interrupted run already wrote.
 */
export async function findCard<T extends CardDef>(
  commandContext: CommandContext,
  type: typeof CardDef,
  match: Record<string, string | null>,
): Promise<T | undefined> {
  let ref = identifyCard(type);
  if (!ref) {
    return undefined;
  }
  let result = await new SearchCardsByQueryCommand(commandContext).execute({
    query: { filter: { on: ref, eq: match } },
  } as any);
  let id = (result?.cardIds ?? [])[0];
  return id ? getCard<T>(commandContext, id) : undefined;
}

/** Every saved card of `type` whose fields equal `match`, fetched. */
export async function findCards<T extends CardDef>(
  commandContext: CommandContext,
  type: typeof CardDef,
  match: Record<string, string | null>,
): Promise<T[]> {
  let ref = identifyCard(type);
  if (!ref) {
    return [];
  }
  let result = await new SearchCardsByQueryCommand(commandContext).execute({
    query: { filter: { on: ref, eq: match } },
  } as any);
  return Promise.all(
    ((result?.cardIds ?? []) as string[]).map((id) =>
      getCard<T>(commandContext, id),
    ),
  );
}
