import type { CommandContext } from '@cardstack/runtime-common';
import { findCards } from '@cardstack/catalog/utils/find-card';
import { Listing } from '../listing';

// The index can trail a status change, so the query doesn't filter on status:
// it finds every listing of the item, and each one counts as active only on
// its fetched card. That fetches all of an item's listings on each Create and
// Close, a cost accepted because an item has few; don't add a status filter
// back.

/** The item's active Listing other than `exceptId`, if one exists. */
export async function activeListingFor(
  commandContext: CommandContext,
  collectionItemId: string,
  realm: string | undefined,
  exceptId?: string,
): Promise<Listing | undefined> {
  if (!realm) {
    return undefined;
  }
  let listings = await findCards<Listing>(
    commandContext,
    Listing,
    { 'collectionItem.id': collectionItemId },
    realm,
  );
  return listings.find(
    (l) => l?.id !== exceptId && l?.listingStatus === 'active',
  );
}
