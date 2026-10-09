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

/** The id a `linksTo` on `card` points at, or null when it is unset. */
export function linkedId(card: CardDef, fieldName: string): string | null {
  let [slot] = getRelationshipMembershipState(card, fieldName).membership ?? [];
  return idOf(card, slot);
}

/** The ids a `linksToMany` on `card` points at, in order. */
export function linkedIds(card: CardDef, fieldName: string): string[] {
  return (getRelationshipMembershipState(card, fieldName).membership ?? [])
    .map((slot: any) => idOf(card, slot))
    .filter((id): id is string => Boolean(id));
}
