import {
  getRelationshipMembershipState,
  getStore,
  type CardDef,
} from 'https://cardstack.com/base/card-api';
import type { Skill } from 'https://cardstack.com/base/skill';
import type { Spec } from 'https://cardstack.com/base/spec';

import type { Listing } from '@cardstack/catalog/catalog-app/listing/listing';

export interface ListingLinks {
  specs: Spec[];
  examples: CardDef[];
  supportingCards: CardDef[];
  skills: Skill[];
}

type ListingLinkField = keyof ListingLinks;

const LISTING_LINK_FIELDS: ListingLinkField[] = [
  'specs',
  'examples',
  'supportingCards',
  'skills',
];

// How each field is named in a broken-link error, and what the user can do
// about it. The spec hint matches the existing "nonexistent type" message in
// listing-install, since "Update Specs" is the listing's own repair action.
const BROKEN_LINK_HINTS: Record<ListingLinkField, [string, string]> = {
  specs: [
    'spec',
    'click "Update Specs" on the listing and make sure all specs are linked',
  ],
  examples: ['example', 'make sure all examples on the listing are linked'],
  supportingCards: [
    'supporting card',
    'make sure all supporting cards on the listing are linked',
  ],
  skills: ['skill', 'make sure all skills on the listing are linked'],
};

// A listing handed to a command (for instance by an AI tool call) may still
// have its `linksToMany` slots loading, and the field getters surface those
// slots, and broken ones, as `undefined`. Reading a field starts its lazy load,
// so read them all, wait for the store to settle, then return only loaded
// cards. A slot that is still not loaded afterwards is a link that will never
// resolve, so it throws an error naming the field and the reference instead of
// letting a planner crash on `undefined`.
export async function loadListingLinks(
  listing: Listing,
): Promise<ListingLinks> {
  for (let fieldName of LISTING_LINK_FIELDS) {
    void listing[fieldName];
  }
  await getStore(listing).loaded();

  let links = {} as ListingLinks;
  let broken: string[] = [];
  for (let fieldName of LISTING_LINK_FIELDS) {
    let { membership } = getRelationshipMembershipState(listing, fieldName);
    let present: CardDef[] = [];
    for (let slot of membership ?? []) {
      if (slot.kind === 'present') {
        present.push(slot.value);
      } else if (slot.kind !== 'not-set') {
        let [label, hint] = BROKEN_LINK_HINTS[fieldName];
        broken.push(
          `Listing ${label} "${slot.reference}" could not be loaded (${slot.kind}). Please ${hint}.`,
        );
      }
    }
    (links as unknown as Record<ListingLinkField, CardDef[]>)[fieldName] =
      present;
  }
  if (broken.length > 0) {
    throw new Error(broken.join('\n'));
  }
  return links;
}
