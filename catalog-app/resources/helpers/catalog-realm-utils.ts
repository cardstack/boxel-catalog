import { realmURL } from 'https://cardstack.com/base/card-api';
import type { CardDef } from 'https://cardstack.com/base/card-api';

/**
 * Returns true if the given card lives in the catalog realm,
 * i.e. its realm URL pathname contains '/catalog/'.
 */
export function isInCatalogRealm(card: CardDef): boolean {
  return !!card[realmURL]?.pathname?.includes('/catalog/');
}
