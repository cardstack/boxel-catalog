import { instanceOf, type CardDef } from '@cardstack/base/card-api';

// A command's `instanceof` compares class identity, and the host can rebuild
// its loader between two runs (a save does it), so a card the store hands back
// can come from another copy of the module the command imported. card-api's
// `instanceOf` compares code refs instead, the same check a linksTo field makes
// on assignment; this wraps it as a type guard.

/** Whether `card` is a `type`, or a subclass of it, whichever loader built it. */
export function isCardOfType<T extends typeof CardDef>(
  card: unknown,
  type: T,
): card is InstanceType<T> {
  return (
    Boolean(card) &&
    typeof card === 'object' &&
    instanceOf(card as CardDef, type)
  );
}
