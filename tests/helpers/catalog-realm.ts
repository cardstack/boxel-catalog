import { ensureTrailingSlash } from '@cardstack/runtime-common';

import ENV from '@cardstack/host/config/environment';

let catalogRealmURL = ensureTrailingSlash(
  ENV.resolvedCatalogRealmURL ?? 'http://localhost:4201/catalog/',
);

// No-op kept so existing tests can keep calling it; the catalog realm is now
// reachable via `catalogRealmURL` without any module preload.
export function setupCatalogRealm(_hooks: any) {}

export { catalogRealmURL };
