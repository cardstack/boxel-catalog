// One-shot hand-off so a gallery card's Remix click can tell the listing
// detail view (a separate render) to focus its remix panel on open.
let pendingRemixListingId: string | undefined;

export function requestRemixFocus(id: string | undefined): void {
  pendingRemixListingId = id;
}

export function consumeRemixFocus(id: string | undefined): boolean {
  if (id && pendingRemixListingId === id) {
    pendingRemixListingId = undefined;
    return true;
  }
  return false;
}
