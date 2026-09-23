import { GetCardCommand } from '@cardstack/boxel-host/commands/get-card';

/**
 * Re-fetch a card before reading through its links — the defensive-link-
 * traversal rule. A caller may hand over a card whose linked fields were never
 * loaded (a queue row, a search result, a card across a command boundary);
 * reading a link off it yields `undefined` and the command quietly does the
 * wrong thing. Shared by the case-management commands.
 */
export async function loaded(context: any, card: any): Promise<any> {
  if (!card?.id) {
    return card;
  }
  return ((await new GetCardCommand(context).execute({
    cardId: card.id,
  } as any)) ?? card) as any;
}

export async function loadedById(
  context: any,
  id?: string | null,
): Promise<any> {
  if (!id) return undefined;
  return ((await new GetCardCommand(context).execute({ cardId: id } as any)) ??
    undefined) as any;
}

// Cards usually title through a computed `cardTitle`; base `title` is often
// unset. One fallback chain for command messages and row labels.
export function displayTitle(card: any, fallback = 'untitled'): string {
  return (card?.cardTitle as string) || (card?.title as string) || fallback;
}
