import {
  getRelationshipMembershipState,
  getStore,
  type CardDef,
} from '@cardstack/base/card-api';

// A command runs outside a render, where a fetched card's links may not have
// loaded and their getters read `undefined`; the stored reference is there
// either way. These read a link's target ids from the relationship itself.

function idOf(owner: CardDef, slot: any): string | null {
  if (!slot || slot.kind === 'not-set') {
    return null;
  }
  if (slot.kind === 'present' && slot.value?.id) {
    return slot.value.id;
  }
  if (!slot.reference) {
    return null;
  }
  return (
    getStore(owner).resolveURL(slot.reference, owner.id)?.href ?? slot.reference
  );
}

/**
 * The id a `linksTo` points at, or null when it is unset. The link is declared
 * on `holder` (`card` itself or a field it contains), and a relative reference
 * resolves against `card`.
 */
export function linkedId(
  card: CardDef,
  fieldName: string,
  holder: object = card,
): string | null {
  let [slot] =
    getRelationshipMembershipState(holder as CardDef, fieldName).membership ??
    [];
  return idOf(card, slot);
}

/** The ids a `linksToMany` points at, in order; `holder` as for `linkedId`. */
export function linkedIds(
  card: CardDef,
  fieldName: string,
  holder: object = card,
): string[] {
  return (
    getRelationshipMembershipState(holder as CardDef, fieldName).membership ??
    []
  )
    .map((slot: any) => idOf(card, slot))
    .filter((id): id is string => Boolean(id));
}
