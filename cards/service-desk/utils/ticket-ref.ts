import { rri } from '@cardstack/runtime-common';

// The Ticket card's ref in the realm this card lives in. Built from the realm
// URL (not an import) because ticket.gts imports these modules back.
export function ticketRefIn(realm: string | undefined) {
  return realm
    ? {
        module: rri(new URL('./service-desk/ticket', realm).href),
        name: 'Ticket',
      }
    : undefined;
}
