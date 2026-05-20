import { CardDef } from 'https://cardstack.com/base/card-api';

// Base class for all playable games in this blog. Subclasses define their
// own isolated/embedded/fitted views; this gives them a common type so a
// single query can surface every game type in one shot.
export class Game extends CardDef {
  static displayName = 'Game';
}
