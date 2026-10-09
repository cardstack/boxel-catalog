import {
  getRelationshipMembershipState,
  getStore,
  type CardDef,
} from '@cardstack/base/card-api';

/**
 * The id a link points at, read from the relationship rather than the linked
 * card. A command runs outside a render, where a fetched card's links may not
 * have loaded and their getters read `undefined`; the reference is there
 * either way. `holder` is the card or contained field that declares the link,
 * and `owner` is the card a relative reference resolves against.
 */
export function linkedId(
  owner: CardDef,
  holder: object,
  fieldName: string,
): string | null {
  let [slot] =
    getRelationshipMembershipState(holder as CardDef, fieldName).membership ??
    [];
  if (!slot || slot.kind === 'not-set') {
    return null;
  }
  if (slot.kind === 'present' && slot.value.id) {
    return slot.value.id;
  }
  return (
    getStore(owner).resolveURL(slot.reference, owner.id)?.href ?? slot.reference
  );
}
