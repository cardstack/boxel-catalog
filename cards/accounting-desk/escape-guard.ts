import { modifier } from 'ember-modifier';

// Inside the Boxel app an Escape that closes a native <dialog> also reaches the card stack and
// closes the card. While a drawer or the palette is open, take Escape at the window first. With
// several open, Escape closes the one opened last, as it would close the topmost dialog.
const escapeLayers: object[] = [];
export const escapeGuard = modifier(
  (_el: Element, [active, close]: [boolean, () => void]) => {
    if (!active) return;
    const layer = {};
    escapeLayers.push(layer);
    const onKey = (e: KeyboardEvent) => {
      if (
        e.key !== 'Escape' ||
        escapeLayers[escapeLayers.length - 1] !== layer
      ) {
        return;
      }
      e.preventDefault();
      e.stopImmediatePropagation();
      close();
    };
    window.addEventListener('keydown', onKey, true);
    return () => {
      window.removeEventListener('keydown', onKey, true);
      escapeLayers.splice(escapeLayers.indexOf(layer), 1);
    };
  },
);
