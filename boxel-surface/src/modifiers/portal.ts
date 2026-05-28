import { modifier } from 'ember-modifier';

/**
 * `{{portal target}}` — appends the element to a DOM target outside
 * the current render tree.
 *
 * K.5 Step B: lives in `boxel-surface` so any host (grid, canvas,
 * future kanban / calendar) can portal lifts past their own clip /
 * overflow / transform ancestors. Hosts that need a different
 * default target (e.g., boxel-canvas portals to `.boxel-canvas` so
 * lifts inherit the canvas's transformed coordinate space) ship
 * their own wrapper.
 *
 * Targets:
 *   - `'body'`            → `document.body`
 *   - any CSS selector    → `element.closest(selector)` first, with
 *                            fallback to `document.body`
 *
 * Restored on teardown — the element is removed entirely so Glimmer
 * doesn't reattach it on the way out.
 */
export default modifier<HTMLElement, [string]>((element, [target]) => {
  const frame = requestAnimationFrame(() => {
    const dest =
      target === 'body'
        ? document.body
        : ((element.closest(target) as HTMLElement | null) ?? document.body);
    if (dest && element.parentElement !== dest) {
      dest.appendChild(element);
    }
  });

  return () => {
    cancelAnimationFrame(frame);
    element.remove();
  };
});
