// `multiUnit` — host-side modifier for multi-unit cells.
//
// When a widget declares the `multi-unit` capability AND renders
// multiple unit elements (each marked with `data-unit-key="<key>"`),
// the host attaches this modifier to the cell wrapper. The modifier:
//
//   1. Scans the cell's DOM for `[data-unit-key]` descendants on
//      mount and on every mutation (chip add/remove, value change).
//   2. Stamps each unit element with `data-ladder-id="${cellId}.${key}"`
//      so surfaceRoot's predicate + lift-id matching all see it as
//      ladder territory.
//   3. Registers each unit in the ladder as `surface: 'unit'` with
//      parent = the cell id, and unregisters on removal.
//   4. Delegates clicks: a click landing inside a `[data-unit-key]`
//      element calls `ladder.select(unitId)` and stops propagation
//      so the surrounding cell click handler doesn't ALSO fire and
//      drop selection back to the cell. Clicks inside the cell but
//      OUTSIDE any unit bubble normally — they reach the cell click
//      handler and select the cell as a unit (the user is selecting
//      "this group of tags", not any specific tag).
//
// USAGE
// =====
//
// In the host (WidgetCell, WidgetRowNode), after deciding the cell
// is multi-unit based on `widget.capabilities.includes('multi-unit')`:
//
//   <div
//     class="cell"
//     data-ladder-id={{cellId}}
//     {{multiUnit ladder cellId}}
//   >
//     <WidgetPreview ... />
//   </div>
//
// The widget's preview component renders chips/tags with
// `data-unit-key` attributes; the modifier wires up the rest. No
// widget changes beyond the data attribute — the widget remains
// surface-agnostic.

import { modifier } from 'ember-modifier';

import type { FocusLadder } from '../focus-ladder.ts';

export interface MultiUnitOptions {
  /** Override the ladder unit surface name. Default 'unit'. Useful
   *  for hosts that want to register sub-units under a different
   *  child surface (rare). */
  unitSurface?: 'unit';
  /** Skip click delegation. The modifier still handles registration
   *  but won't add a click handler — useful if the host already has
   *  per-unit click logic via another path. */
  skipClick?: boolean;
}

const multiUnit = modifier<{
  Element: HTMLElement;
  Args: {
    Positional: [FocusLadder | undefined, string | undefined];
    Named: MultiUnitOptions;
  };
}>((cell, [ladder, cellId], opts = {}) => {
  // Tolerate missing ladder / cellId — the host may attach the
  // modifier unconditionally but only some cells participate in
  // the ladder. No-op when either is missing.
  if (!ladder || !cellId) return;
  // Track which unit ids we currently have registered, so we can
  // diff-and-update on each mutation (add new, drop old).
  const registry = new Map<string, () => void>();

  // Paint focus / selection chrome on each unit based on ladder
  // state. CRITICAL: this function reads `@tracked` ladder state
  // (`isFocused`, `isSelected`). It MUST NOT run inside the
  // modifier's setup scope — ember-modifier's autotrack would
  // capture those reads and re-setup the modifier on every ladder
  // mutation (causing the registry + observer to re-create
  // constantly, breaking subscribe). All paint calls run via
  // `queueMicrotask` (initial paint) or via the subscribe callback
  // (subsequent), both of which execute OUTSIDE the autotrack
  // scope.
  const paint = (): void => {
    for (const id of registry.keys()) {
      const el = cell.querySelector<HTMLElement>(
        `[data-ladder-id="${CSS.escape(id)}"]`,
      );
      if (!el) continue;
      el.classList.toggle('is-ladder-focused', ladder.isFocused(id));
      el.classList.toggle('is-ladder-selected', ladder.isSelected(id));
    }
  };

  const sync = (): void => {
    const units = cell.querySelectorAll<HTMLElement>('[data-unit-key]');
    const seen = new Set<string>();
    for (const unit of Array.from(units)) {
      const key = unit.getAttribute('data-unit-key');
      if (!key) continue;
      const fullId = `${cellId}.${key}`;
      seen.add(fullId);
      // Stamp ladder id (idempotent — surfaceRoot reads this)
      const existing = unit.getAttribute('data-ladder-id');
      if (existing !== fullId) unit.setAttribute('data-ladder-id', fullId);
      // Register if new
      if (!registry.has(fullId)) {
        const cleanup = ladder.register({
          id: fullId,
          surface: 'unit',
          parentId: cellId,
        });
        registry.set(fullId, cleanup);
      }
    }
    // Drop stale registrations (units that no longer exist)
    for (const [id, cleanup] of registry) {
      if (!seen.has(id)) {
        cleanup();
        registry.delete(id);
      }
    }
    // NOTE: do NOT call paint() here — would auto-track tracked
    // ladder reads inside the modifier scope. paint() runs via
    // queueMicrotask + subscribe instead.
  };

  // Initial pass after the widget renders its units.
  sync();

  // MutationObserver re-syncs on any child / attribute change.
  // Watching `data-unit-key` specifically lets widgets re-render
  // their units (e.g., chips re-rendering on value change) without
  // dropping registrations needlessly — only the diff applies.
  const observer = new MutationObserver(sync);
  observer.observe(cell, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ['data-unit-key'],
  });

  // Click delegation. We listen on the cell IN CAPTURE PHASE so we
  // run BEFORE the cell's own bubble-phase click handlers (the
  // template's `{{on "click" handleCellSelect}}` would otherwise
  // also fire and demote selection back to the cell).
  // stopImmediatePropagation prevents OTHER handlers on the same
  // element from running too — `stopPropagation` alone only stops
  // the bubble to ancestors, not siblings on the same element.
  const onClick = (event: MouseEvent): void => {
    if (opts.skipClick) return;
    const target = event.target;
    if (!(target instanceof Element)) return;
    const unit = target.closest<HTMLElement>('[data-unit-key]');
    if (!unit || !cell.contains(unit)) return;
    const fullId = unit.getAttribute('data-ladder-id');
    if (!fullId) return;
    event.stopPropagation();
    event.stopImmediatePropagation();
    ladder.select(fullId, {
      additive: event.metaKey || event.ctrlKey,
      range: event.shiftKey,
    });
  };
  cell.addEventListener('click', onClick, true);

  // Subscribe to ladder so focus/selection chrome stays in sync
  // with state changes (keyboard nav, click in another pane,
  // background-click clear). The subscribe CALLBACK runs outside
  // the modifier's autotrack scope, so reading ladder state inside
  // paint() doesn't trigger a modifier re-setup.
  const unsubscribe = ladder.subscribe(() => paint());

  // Initial paint — deferred via microtask so it runs AFTER the
  // modifier setup completes, escaping ember-modifier's autotrack
  // scope. Without this, the first paint() captures every tracked
  // ladder read and forces a teardown+setup on every mutation.
  queueMicrotask(paint);

  return () => {
    observer.disconnect();
    cell.removeEventListener('click', onClick);
    unsubscribe();
    for (const cleanup of registry.values()) cleanup();
    registry.clear();
  };
});

export default multiUnit;
