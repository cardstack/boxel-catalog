import Component from '@glimmer/component';
import { on } from '@ember/modifier';
import { modifier } from 'ember-modifier';
import { consume } from 'ember-provide-consume-context';
import {
  autoUpdate,
  computePosition,
  flip,
  hide,
  offset,
  shift,
} from '@floating-ui/dom';
import type { Placement, Strategy } from '@floating-ui/dom';

import { SURFACE_LAYERS, type SurfaceLayerTier } from '../layer-manager.ts';
import {
  createSurfaceScopeRelay,
  SurfaceScopeContextName,
  type SurfaceScopeRelay,
} from '../scope-relay.ts';
import surfaceScopeRelay from '../modifiers/scope-relay.ts';
import type { FocusLadder } from '../focus-ladder.ts';
import type { SurfaceRuntime } from '../surface-runtime.ts';
import { LiftContextName, type LiftManager } from '../lift-edges.ts';
import {
  ladderForSurfaceElement,
  liftManagerForSurfaceElement,
  registerSurfaceDomRoot,
  registerSurfaceLiftDomRoot,
  surfaceRuntimeForElement,
} from '../dom-registry.ts';
import {
  LadderContextName,
  SurfaceRuntimeContextName,
  ModeContextName,
  InspectContextName,
} from '../surface-contexts.ts';

/**
 * `<Lift>` — anchored floating surface that hosts a focused
 * interaction next to a source element.
 *
 * **The vocabulary shift.** "Popover" is a CSS mechanism;
 * "lift" is a SEMANTIC. A lift RAISES a focused something out of
 * the source's small footprint without taking the user away from
 * the source.
 *
 * **Four orthogonal dimensions** drive the visual + behavioral
 * variant, all sourced from the negotiated `Contract`:
 *
 *   kind          'details' | 'preview' | 'edit' | 'tools'
 *   placement     'attached' | 'shadow' | 'plane'
 *   size          'compact' | 'comfortable' | 'spacious' | 'auto'
 *   backdrop      'none' | 'tint' | 'blur' | 'scrim'
 *   elevation     'flat' | 'raised' | 'elevated' | 'modal'
 *
 * Plus `keyboardModel` ('pick' | 'edit-number' | 'edit-text' |
 * 'compose') which doesn't paint, but threads through to the body
 * so inner picker primitives can route keystrokes correctly.
 *
 * **What the host owns.** Open / close state, kind state, the
 * actual content (yielded as the default block), what each kind
 * means in the host's domain. The Lift owns positioning, dismissal
 * plumbing (Esc + click-out), focus enter / restore, the per-kind
 * + per-elevation visual chrome, and the optional scrim backdrop.
 *
 * **Chrome simplification.** The escalation toolbar is OFF by
 * default. When `canEscalateTo` lists more than the current kind,
 * a single compact glyph button appears in the top-right corner
 * (✎ for edit, ⓘ for details, etc.). One click escalates. No
 * labels, no full toolbar — frees the body for content.
 */

export type LiftKind = 'details' | 'preview' | 'edit' | 'tools';

export type LiftPlacement = 'attached' | 'shadow' | 'plane';

export type LiftSize = 'compact' | 'comfortable' | 'spacious' | 'auto';

export type LiftBackdrop = 'none' | 'tint' | 'blur' | 'scrim';

export type LiftElevation = 'flat' | 'raised' | 'elevated' | 'modal';

export type LiftKeyboardModel =
  | 'pick'
  | 'edit-number'
  | 'edit-text'
  | 'compose';

export interface LiftSignature {
  Args: {
    /** CSS selector velcro / shadowAnchor uses to find the source. */
    anchor: string;
    /** When false, lift is unmounted. Toggling preserves the lift's
     *  surrounding `<Lift>` invocation so re-opens are cheap. */
    open: boolean;
    /** Lift kind — drives the per-kind chrome variant + body content
     *  (host yields different content per kind). */
    kind: LiftKind;
    /** Geometric mounting strategy. Default 'attached'. */
    placementMode?: LiftPlacement;
    /** Geometric size class. Default 'comfortable'. Drives min /
     *  max width + height via CSS variables. */
    size?: LiftSize;
    /** Visual separation token. Default depends on kind. */
    backdrop?: LiftBackdrop;
    /** Elevation tier. Default depends on kind + placement. */
    elevation?: LiftElevation;
    /** Keyboard model — names a finite-state model the body's
     *  picker primitives honor. The Lift exposes it as a data attr
     *  so primitives can read it; it doesn't drive Lift's own
     *  keystroke handling. */
    keyboardModel?: LiftKeyboardModel;
    /** Stable per-open token. Re-renders of the same open lift keep
     *  this token so autofocus runs once for the open interaction,
     *  not after every source-data update. */
    focusToken?: string | number;
    /** Move DOM focus into the lift on open + restore on close.
     *  Default true except for `details` kind. */
    autoFocus?: boolean;
    /** Optional kinds the user can escalate to. When the array
     *  contains kinds OTHER than the current `@kind`, a corner
     *  escalation glyph button appears. Single-kind contracts
     *  (just the current kind) get NO chrome. */
    canEscalateTo?: LiftKind[];
    /** Fired when the user clicks an escalation glyph. */
    onEscalate?: (next: LiftKind) => void;
    /** Fired on Esc / outside-click. Host sets `@open=false`. */
    onDismiss?: () => void;
    /** Optional explicit surface layer tier. Defaults from placement/elevation. */
    layerTier?: SurfaceLayerTier;
    /** Optional fixed z-index for hosts that already allocated a layer. */
    zIndex?: number;
    /** Velcro placement override (only used when placementMode is
     *  'attached'). Default 'bottom-start'. */
    placement?: Placement;
    /** Visual scale multiplier for the lift surface. Generalizes
     *  the "scale of the rendering environment" — used by any
     *  scalable host (canvas zoom, 3D scene camera distance, future
     *  scene-graph hosts) to scale the LIFT in lockstep with how
     *  the rest of the host's content is being scaled.
     *
     *  The host computes a DAMPED multiplier (the lift shouldn't
     *  scale 1:1 with the env — at canvas zoom 0.25 you don't want
     *  a popover at 25% of normal size, you want it noticeably
     *  smaller but still readable). Use `dampedRelativeScale(env)`
     *  from boxel-surface for a sane default curve.
     *
     *  Applied via the CSS `zoom` property (standardized; supported
     *  in Chrome, Safari, Edge, and Firefox 126+) so the entire
     *  surface including its measured box scales — velcro's anchor
     *  positioning reads the new bbox correctly. Default 1 (no
     *  scaling — viewport scale).
     *
     *  IGNORED for `'plane'` placement (modal lifts are centered on
     *  the viewport, not anchored to scalable host content; they
     *  always render at viewport scale). */
    relativeScale?: number;
  };
  Blocks: {
    default: [LiftKind];
  };
  Element: HTMLDivElement;
}

/** Esc / click-out dismiss modifier.
 *
 *  Capture-phase listeners — they fire BEFORE any bubble-phase
 *  handler in the lift body OR in the host's surrounding shell.
 *  Both paths call `stopPropagation()` so the same Esc / pointerdown
 *  doesn't ALSO trigger the host's grid-key handler (clearing cell
 *  focus) or the next cell's openEdit (when the user clicked from
 *  one lift directly into another cell). The lift owns dismissal,
 *  full stop. */
const dismissOnOutside = modifier(
  (_el: HTMLElement, [onDismiss]: [(() => void) | undefined]) => {
    if (!onDismiss) return;
    const onPointer = (event: PointerEvent): void => {
      const target = event.target as Element | null;
      if (!target) return;
      // Click inside any lift body OR on a lift anchor — let it
      // through (the anchor click reopens a fresh lift; the body
      // click is interactive). Otherwise the click is "outside" —
      // dismiss + don't let the click also fire other handlers
      // (e.g., a sibling cell's onSelect). Without this, clicking
      // from one cell's open lift into another cell would close
      // lift A then immediately open lift B with stale focus.
      if (target.closest('[data-bx-lift]')) return;
      if (target.closest('[data-bx-lift-anchor]')) return;
      // ember-power-select renders its dropdown options in a portal at
      // document.body — treat that portal as "inside" so picking an
      // option from a BoxelSelect within the lift does not dismiss it.
      if (target.closest('.ember-basic-dropdown-content')) return;
      onDismiss();
    };
    const onKey = (event: KeyboardEvent): void => {
      if (event.key === 'Escape') {
        event.preventDefault();
        // Stop here — don't let Esc bubble past the lift to the
        // host's keyboard handler (which would clear cell focus
        // OR cancel an unrelated state). Esc inside a lift means
        // ONE thing: close THIS lift.
        event.stopPropagation();
        onDismiss();
      }
    };
    window.addEventListener('pointerdown', onPointer, true);
    window.addEventListener('keydown', onKey, true);
    return () => {
      window.removeEventListener('pointerdown', onPointer, true);
      window.removeEventListener('keydown', onKey, true);
    };
  },
);

const allocateLiftLayer = modifier(
  (
    element: HTMLElement,
    [tier, fixedZIndex]: [SurfaceLayerTier, number | undefined],
  ) => {
    const z = fixedZIndex ?? SURFACE_LAYERS.allocate(tier);
    element.style.setProperty('--bx-lift-z', String(z));
    element.dataset['surfaceLayerTier'] = tier;
    element.dataset['surfaceLayerZ'] = String(z);

    return () => {
      if (fixedZIndex === undefined) {
        SURFACE_LAYERS.release(z);
      }
      element.style.removeProperty('--bx-lift-z');
      delete element.dataset['surfaceLayerTier'];
      delete element.dataset['surfaceLayerZ'];
    };
  },
);

const liftSurfaceRoot = modifier(
  (
    element: HTMLElement,
    _positional: [],
    named: {
      anchor?: string;
      ladder?: FocusLadder;
      runtime?: SurfaceRuntime;
      liftManager?: LiftManager;
      mode?: 'use' | 'change' | 'inspect';
      inspect?: boolean;
    },
  ) => {
    const anchor = named.anchor
      ? element.ownerDocument.querySelector<HTMLElement>(named.anchor)
      : null;
    const ladder =
      named.ladder ?? (anchor ? ladderForSurfaceElement(anchor) : undefined);
    const runtime =
      named.runtime ?? (anchor ? surfaceRuntimeForElement(anchor) : undefined);
    const liftManager =
      named.liftManager ??
      (anchor ? liftManagerForSurfaceElement(anchor) : undefined);
    const modeRoot = anchor?.closest<HTMLElement>('[data-surface-mode]');
    const inspectRoot = anchor?.closest<HTMLElement>('[data-surface-inspect]');
    const priorMode = element.getAttribute('data-surface-mode');
    const priorInspect = element.getAttribute('data-surface-inspect');
    const syncModeAndInspect = (): void => {
      const mode =
        named.mode ??
        (modeRoot?.dataset['surfaceMode'] as
          | 'use'
          | 'change'
          | 'inspect'
          | undefined);
      const inspectAttr =
        named.inspect ?? inspectRoot?.getAttribute('data-surface-inspect');
      const inspect =
        typeof inspectAttr === 'boolean'
          ? inspectAttr
          : inspectAttr === 'true' || inspectAttr === '';
      element.setAttribute('data-surface-mode', mode ?? 'use');
      element.setAttribute('data-surface-inspect', String(inspect));
    };
    syncModeAndInspect();
    element.setAttribute('data-surface-portaled-root', 'lift');
    const unregisterRoot = ladder
      ? registerSurfaceDomRoot(element, ladder, runtime)
      : undefined;
    const unregisterLiftRoot = liftManager
      ? registerSurfaceLiftDomRoot(element, liftManager)
      : undefined;
    const modeObserver = new MutationObserver(syncModeAndInspect);
    if (modeRoot) {
      modeObserver.observe(modeRoot, {
        attributes: true,
        attributeFilter: ['data-surface-mode'],
      });
    }
    if (inspectRoot && inspectRoot !== modeRoot) {
      modeObserver.observe(inspectRoot, {
        attributes: true,
        attributeFilter: ['data-surface-inspect'],
      });
    }

    return () => {
      modeObserver.disconnect();
      unregisterLiftRoot?.();
      unregisterRoot?.();
      element.removeAttribute('data-surface-portaled-root');
      if (priorMode === null) element.removeAttribute('data-surface-mode');
      else element.setAttribute('data-surface-mode', priorMode);
      if (priorInspect === null)
        element.removeAttribute('data-surface-inspect');
      else element.setAttribute('data-surface-inspect', priorInspect);
    };
  },
);

/** Shadow-anchor modifier — overlays the lift on the anchor's bbox.
 *  Sets top / left / min-width from anchor's getBoundingClientRect.
 *  Clamps to the viewport: if the lift's natural width would extend
 *  past the right edge, shifts left to keep the right edge inside. */
const shadowAnchor = modifier((element: HTMLElement, [selector]: [string]) => {
  const anchorEl = (): HTMLElement | null =>
    document.querySelector<HTMLElement>(selector);
  const update = (): void => {
    const a = anchorEl();
    if (!a) return;
    const r = a.getBoundingClientRect();
    // Reset position-related styles before measuring so a previous
    // run's shifts don't pollute the new computation.
    element.style.position = 'absolute';
    element.style.top = `${window.scrollY + r.top}px`;
    element.style.left = `${window.scrollX + r.left}px`;
    element.style.minWidth = `${Math.round(r.width)}px`;
    // Now measure the lift's actual width (after layout settled
    // with the new min-width applied) and clamp to viewport.
    requestAnimationFrame(() => {
      const lr = element.getBoundingClientRect();
      const overflowRight = lr.right - window.innerWidth + 8; // 8px gutter
      if (overflowRight > 0) {
        const newLeft = window.scrollX + r.left - overflowRight;
        element.style.left = `${Math.max(window.scrollX + 8, newLeft)}px`;
      }
      // Same for vertical — if extending past viewport bottom,
      // shift up so we don't get cut off.
      const overflowBottom = lr.bottom - window.innerHeight + 8;
      if (overflowBottom > 0) {
        const newTop = window.scrollY + r.top - overflowBottom;
        element.style.top = `${Math.max(window.scrollY + 8, newTop)}px`;
      }
    });
  };
  update();
  const ro = new ResizeObserver(update);
  const a = anchorEl();
  if (a) ro.observe(a);
  window.addEventListener('scroll', update, true);
  window.addEventListener('resize', update);
  return (): void => {
    ro.disconnect();
    window.removeEventListener('scroll', update, true);
    window.removeEventListener('resize', update);
  };
});

const anchoredLift = modifier(
  (
    floatingElement: HTMLElement,
    [selector]: [string],
    {
      placement = 'bottom-start',
      offsetOptions = 0,
      strategy = 'fixed',
    }: {
      placement?: Placement;
      offsetOptions?: number;
      strategy?: Strategy;
    } = {},
  ) => {
    let frame = 0;
    let destroyed = false;
    let lastTop = '';
    let lastLeft = '';
    let lastVisibility = '';

    const referenceElement = (): HTMLElement | SVGElement | null =>
      document.querySelector<HTMLElement | SVGElement>(selector);

    Object.assign(floatingElement.style, {
      position: strategy,
      top: '0px',
      left: '0px',
      margin: '0',
    });

    const apply = (top: string, left: string, visibility: string): void => {
      if (
        top === lastTop &&
        left === lastLeft &&
        visibility === lastVisibility
      ) {
        return;
      }

      lastTop = top;
      lastLeft = left;
      lastVisibility = visibility;
      Object.assign(floatingElement.style, {
        top,
        left,
        margin: '0',
        visibility,
      });
    };

    const update = async (): Promise<void> => {
      frame = 0;
      const reference = referenceElement();
      if (!reference) {
        apply(lastTop || '0px', lastLeft || '0px', 'hidden');
        return;
      }

      const { middlewareData, x, y } = await computePosition(
        reference,
        floatingElement,
        {
          middleware: [
            offset(offsetOptions),
            flip(),
            shift({ padding: 8 }),
            hide({ strategy: 'referenceHidden' }),
          ],
          placement,
          strategy,
        },
      );
      if (destroyed) return;

      apply(
        `${Math.round(y)}px`,
        `${Math.round(x)}px`,
        middlewareData.hide?.referenceHidden ? 'hidden' : 'visible',
      );
    };

    const schedule = (): void => {
      if (frame !== 0) return;
      frame = requestAnimationFrame(() => {
        void update();
      });
    };

    schedule();
    const reference = referenceElement();
    const cleanup = reference
      ? autoUpdate(reference, floatingElement, schedule, {
          ancestorResize: true,
          ancestorScroll: true,
          elementResize: true,
          layoutShift: false,
          animationFrame: false,
        })
      : undefined;

    return (): void => {
      destroyed = true;
      cancelAnimationFrame(frame);
      cleanup?.();
    };
  },
);

/** Focus-management modifier. Auto-focuses first focusable in body
 *  on mount; restores DOM focus to the closest focusable ancestor
 *  of the anchor on unmount. */
const focusedLiftTokens = new Set<string>();

function liftFocusableSelector(): string {
  return [
    'button:not([disabled]):not([tabindex="-1"])',
    'input:not([type="hidden"]):not([disabled]):not([tabindex="-1"])',
    'select:not([disabled]):not([tabindex="-1"])',
    'textarea:not([disabled]):not([tabindex="-1"])',
    '[contenteditable=""]:not([tabindex="-1"])',
    '[contenteditable="true"]:not([tabindex="-1"])',
    '[tabindex]:not([tabindex="-1"])',
  ].join(',');
}

function liftEditorSelector(): string {
  return [
    'input:not([type="hidden"]):not([disabled]):not([tabindex="-1"])',
    'textarea:not([disabled]):not([tabindex="-1"])',
    'select:not([disabled]):not([tabindex="-1"])',
    '[contenteditable=""]:not([tabindex="-1"])',
    '[contenteditable="true"]:not([tabindex="-1"])',
  ].join(',');
}

function visibleFocusables(element: HTMLElement): HTMLElement[] {
  return Array.from(
    element.querySelectorAll<HTMLElement>(liftFocusableSelector()),
  ).filter((candidate) => {
    if (!candidate.isConnected) return false;
    if (candidate.closest('[inert]')) return false;
    const rects = candidate.getClientRects();
    return rects.length > 0 || candidate === document.activeElement;
  });
}

function firstLiftFocusTarget(element: HTMLElement): HTMLElement | null {
  const body = element.querySelector<HTMLElement>('.bx-lift__body') ?? element;
  const keyboardModel = element.getAttribute('data-bx-lift-keyboard-model');
  if (keyboardModel === 'pick') {
    const listbox = body.querySelector<HTMLElement>(
      '[role="listbox"]:not([tabindex="-1"])',
    );
    if (listbox) return listbox;
  }
  const autofocus = body.querySelector<HTMLElement>('[autofocus]');
  if (autofocus) return autofocus;
  if (
    keyboardModel === 'edit-text' ||
    keyboardModel === 'edit-number' ||
    keyboardModel === 'compose'
  ) {
    const editor = body.querySelector<HTMLElement>(liftEditorSelector());
    if (editor) return editor;
  }
  return body.querySelector<HTMLElement>(liftFocusableSelector());
}

function focusLiftTarget(target: HTMLElement): void {
  target.focus({ preventScroll: true });
  if (target instanceof HTMLInputElement) {
    if (
      target.type === 'text' ||
      target.type === 'number' ||
      target.type === 'search' ||
      target.type === 'url' ||
      target.type === 'tel' ||
      target.type === 'email' ||
      target.type === 'password'
    ) {
      target.select();
    }
  } else if (target instanceof HTMLTextAreaElement) {
    target.select();
  }
}

type ReroutedKeyboardEvent = KeyboardEvent & {
  __boxelLiftKeyboardRerouted?: true;
};

function isPlainTextKey(event: KeyboardEvent): boolean {
  return (
    event.key.length === 1 && !event.metaKey && !event.ctrlKey && !event.altKey
  );
}

function isPickerNavigationKey(event: KeyboardEvent): boolean {
  return (
    event.key === 'ArrowDown' ||
    event.key === 'ArrowUp' ||
    event.key === 'Home' ||
    event.key === 'End' ||
    event.key === 'Enter' ||
    event.key === 'Tab' ||
    event.key === ' ' ||
    event.key === 'Spacebar' ||
    isPlainTextKey(event)
  );
}

function isEditingKey(event: KeyboardEvent): boolean {
  if (event.metaKey || event.ctrlKey || event.altKey) return false;
  return (
    event.key === 'Enter' ||
    event.key === 'Tab' ||
    event.key.startsWith('Arrow') ||
    event.key === 'Home' ||
    event.key === 'End' ||
    event.key === 'PageUp' ||
    event.key === 'PageDown' ||
    event.key === 'Backspace' ||
    event.key === 'Delete' ||
    isPlainTextKey(event)
  );
}

function liftKeyboardModelOwnsEvent(
  element: HTMLElement,
  event: KeyboardEvent,
): boolean {
  const keyboardModel = element.getAttribute('data-bx-lift-keyboard-model');
  if (keyboardModel === 'pick') return isPickerNavigationKey(event);
  if (
    keyboardModel === 'edit-text' ||
    keyboardModel === 'edit-number' ||
    keyboardModel === 'compose'
  ) {
    return isEditingKey(event);
  }
  return false;
}

function topmostKeyboardLift(): HTMLElement | null {
  const lifts = Array.from(
    document.querySelectorAll<HTMLElement>(
      '[data-bx-lift][data-bx-lift-keyboard-lock="true"]',
    ),
  );
  return (
    lifts.sort((a, b) => {
      const za = Number(a.dataset['surfaceLayerZ'] ?? 0);
      const zb = Number(b.dataset['surfaceLayerZ'] ?? 0);
      return zb - za;
    })[0] ?? null
  );
}

function cloneKeyboardEvent(event: KeyboardEvent): ReroutedKeyboardEvent {
  const next = new KeyboardEvent(event.type, {
    key: event.key,
    code: event.code,
    location: event.location,
    altKey: event.altKey,
    ctrlKey: event.ctrlKey,
    metaKey: event.metaKey,
    shiftKey: event.shiftKey,
    repeat: event.repeat,
    isComposing: event.isComposing,
    bubbles: true,
    cancelable: true,
  }) as ReroutedKeyboardEvent;
  next.__boxelLiftKeyboardRerouted = true;
  return next;
}

const liftFocusModifier = modifier(
  (
    element: HTMLElement,
    [focusToken]: [string | number | undefined],
    { enabled = true }: { enabled?: boolean } = {},
  ) => {
    if (!enabled) return;
    const initial = document.activeElement as HTMLElement | null;
    const previouslyFocused =
      initial && initial !== document.body ? initial : null;
    const token = focusToken === undefined ? undefined : String(focusToken);
    let frame = 0;
    let attempts = 0;
    const focusWhenReady = (): void => {
      if (token && focusedLiftTokens.has(token)) return;
      // Pick model: prefer the LISTBOX (Spotlight idiom). Compose
      // model: prefer the editor's own input (calendar's date input,
      // formula builder's expression box). Other models: first
      // focusable wins.
      const target = firstLiftFocusTarget(element);
      if (!target) {
        if (attempts++ < 4) {
          frame = requestAnimationFrame(focusWhenReady);
        }
        return;
      }
      focusLiftTarget(target);
      if (token) focusedLiftTokens.add(token);
    };
    frame = requestAnimationFrame(focusWhenReady);
    const anchorSelector = element.getAttribute('data-bx-lift-anchor-selector');
    return (): void => {
      cancelAnimationFrame(frame);
      const active = document.activeElement as HTMLElement | null;
      if (active?.closest('[data-bx-lift]')) return;
      const focusEscaped =
        active !== null &&
        active !== document.body &&
        !element.contains(active);
      if (focusEscaped) return;
      const isFocusable = (el: HTMLElement): boolean => {
        if (el.hasAttribute('disabled')) return false;
        const tag = el.tagName;
        if (
          tag === 'INPUT' ||
          tag === 'TEXTAREA' ||
          tag === 'SELECT' ||
          tag === 'BUTTON' ||
          tag === 'A'
        ) {
          return true;
        }
        if (el.hasAttribute('contenteditable')) return true;
        const ti = el.getAttribute('tabindex');
        if (ti !== null && ti !== '-1') return true;
        return false;
      };
      const findFocusable = (start: HTMLElement | null): HTMLElement | null => {
        let cur: HTMLElement | null = start;
        while (cur && cur !== document.body) {
          if (isFocusable(cur)) return cur;
          cur = cur.parentElement;
        }
        return start;
      };
      let restoreTo: HTMLElement | null = null;
      if (previouslyFocused && document.contains(previouslyFocused)) {
        restoreTo = isFocusable(previouslyFocused)
          ? previouslyFocused
          : findFocusable(previouslyFocused);
      }
      if (!restoreTo && anchorSelector) {
        const anchor = document.querySelector<HTMLElement>(anchorSelector);
        restoreTo = findFocusable(anchor);
      }
      if (!restoreTo) return;
      restoreTo.focus();
      setTimeout(() => {
        if (restoreTo && document.contains(restoreTo)) restoreTo.focus();
      }, 0);
    };
  },
);

/** Delegates stale-focus keyboard events into the active lift body.
 *
 *  This is the engine-level version of the old grid-demo pattern:
 *  while an edit/tools lift is open, Arrow/Enter/Space/type-ahead
 *  belong to the lifted control, even if the browser still reports
 *  DOM focus on the source cell or parent grid. The lift focuses its
 *  negotiated target (`keyboardModel="pick"` prefers listbox;
 *  text/number/compose prefer the editor) and re-dispatches a cloned
 *  key event there. Host grids should see neither the stale event nor
 *  a parent navigation command.
 */
const delegateLiftKeyboardModifier = modifier(
  (
    element: HTMLElement,
    _positional: never[],
    { enabled = true }: { enabled?: boolean } = {},
  ) => {
    if (!enabled) return;

    const onKeydown = (event: KeyboardEvent): void => {
      const routed = event as ReroutedKeyboardEvent;
      if (routed.__boxelLiftKeyboardRerouted) return;
      if (event.defaultPrevented) return;
      if (event.key === 'Escape') return;
      if (topmostKeyboardLift() !== element) return;

      const target = event.target instanceof Element ? event.target : null;
      const active =
        document.activeElement instanceof Element
          ? document.activeElement
          : null;
      // Treat ember-power-select's portal as logically inside the lift —
      // keystrokes in its search/options must NOT be hijacked by the lift.
      const insideLift = (node: Element): boolean => {
        if (element.contains(node)) return true;
        if (node.closest('.ember-basic-dropdown-content')) return true;
        return false;
      };
      if (target && insideLift(target)) return;
      if (active && insideLift(active)) return;
      if (!liftKeyboardModelOwnsEvent(element, event)) return;

      const delegateTarget = firstLiftFocusTarget(element);
      if (!delegateTarget) return;

      event.preventDefault();
      event.stopImmediatePropagation();
      focusLiftTarget(delegateTarget);
      delegateTarget.dispatchEvent(cloneKeyboardEvent(event));
    };

    window.addEventListener('keydown', onKeydown, true);
    return () => window.removeEventListener('keydown', onKeydown, true);
  },
);

/** Keeps edit/plane lifts in control of DOM focus while they are open.
 *
 *  Surface selection remains on the source coordinate; the lift owns
 *  the active editor. This mirrors grid/canvas lifted editing: Tab
 *  cycles inside the raised editor, and any programmatic focus steal
 *  back to the source is corrected on the next focusin/frame. */
const trapLiftFocusModifier = modifier(
  (
    element: HTMLElement,
    _positional: never[],
    { enabled = true }: { enabled?: boolean } = {},
  ) => {
    if (!enabled) return;

    let lastFocused: HTMLElement | null = null;
    let allowOutsideFocusUntil = 0;

    const focusFallback = (): void => {
      requestAnimationFrame(() => {
        if (!element.isConnected) return;
        if (
          document.activeElement instanceof Element &&
          element.contains(document.activeElement)
        ) {
          return;
        }
        const target =
          (lastFocused?.isConnected && element.contains(lastFocused)
            ? lastFocused
            : null) ?? firstLiftFocusTarget(element);
        target?.focus({ preventScroll: true });
      });
    };

    const onKeydown = (event: KeyboardEvent): void => {
      if (event.key !== 'Tab') return;
      const focusables = visibleFocusables(element);
      if (focusables.length === 0) return;

      event.preventDefault();
      event.stopPropagation();

      const active = document.activeElement as HTMLElement | null;
      const currentIndex = active ? focusables.indexOf(active) : -1;
      const nextIndex =
        currentIndex === -1
          ? 0
          : event.shiftKey
            ? (currentIndex - 1 + focusables.length) % focusables.length
            : (currentIndex + 1) % focusables.length;
      const next = focusables[nextIndex];
      if (!next) return;
      lastFocused = next;
      next.focus({ preventScroll: true });
    };

    // Treat ember-power-select's portal (rendered at document.body) as
    // logically inside the lift — its dropdown options sit outside our
    // element subtree but represent interaction with our content.
    const isInsideOrPortal = (target: Element): boolean => {
      if (element.contains(target)) return true;
      if (target.closest('.ember-basic-dropdown-content')) return true;
      return false;
    };

    const onFocusin = (event: FocusEvent): void => {
      const target = event.target;
      if (!(target instanceof HTMLElement)) return;
      if (isInsideOrPortal(target)) {
        lastFocused = target;
        return;
      }
      if (Date.now() < allowOutsideFocusUntil) return;
      focusFallback();
    };

    const onPointerdown = (event: PointerEvent): void => {
      const target = event.target;
      if (target instanceof Element && isInsideOrPortal(target)) return;
      // Outside pointerdown is normally a dismiss gesture. Give the
      // close path a short window so the trap does not fight the
      // user's intentional click outside the lift.
      allowOutsideFocusUntil = Date.now() + 250;
    };

    element.addEventListener('keydown', onKeydown, true);
    window.addEventListener('focusin', onFocusin, true);
    window.addEventListener('pointerdown', onPointerdown, true);

    return () => {
      element.removeEventListener('keydown', onKeydown, true);
      window.removeEventListener('focusin', onFocusin, true);
      window.removeEventListener('pointerdown', onPointerdown, true);
    };
  },
);

let nextLiftInstanceId = 0;

const cleanupClosedLiftModifier = modifier(
  (_element: HTMLElement, [open, instanceId]: [boolean, string]) => {
    let frame = 0;
    if (!open) {
      frame = requestAnimationFrame(() => {
        for (const stale of document.querySelectorAll<HTMLElement>(
          `[data-bx-lift-instance="${instanceId}"]`,
        )) {
          stale.remove();
        }
      });
    }

    return () => {
      cancelAnimationFrame(frame);
    };
  },
);

export default class Lift extends Component<LiftSignature> {
  readonly instanceId = `bx-lift-${++nextLiftInstanceId}`;
  @consume(SurfaceScopeContextName) declare inheritedScopeRelay:
    | SurfaceScopeRelay
    | undefined;
  @consume(LadderContextName) declare inheritedLadder: FocusLadder | undefined;
  @consume(SurfaceRuntimeContextName) declare inheritedRuntime:
    | SurfaceRuntime
    | undefined;
  @consume(LiftContextName) declare inheritedLiftManager:
    | LiftManager
    | undefined;
  @consume(ModeContextName) declare inheritedMode:
    | 'use'
    | 'change'
    | 'inspect'
    | undefined;
  @consume(InspectContextName) declare inheritedInspect: boolean | undefined;
  private localScopeRelay: SurfaceScopeRelay | undefined;

  get scopeRelay(): SurfaceScopeRelay {
    let relay = this.localScopeRelay;
    if (!relay || relay.parent !== this.inheritedScopeRelay) {
      relay = createSurfaceScopeRelay(this.inheritedScopeRelay);
      // eslint-disable-next-line ember/no-side-effects
      this.localScopeRelay = relay;
    }
    return relay;
  }

  // ─── arg defaults ───────────────────────────────────────────────

  get portalTarget(): HTMLElement {
    if (typeof document === 'undefined') {
      throw new Error('<Lift> requires a browser document to portal into.');
    }
    return document.body;
  }

  get effectivePlacement(): Placement {
    return this.args.placement ?? 'bottom-start';
  }

  get placementMode(): LiftPlacement {
    return this.args.placementMode ?? 'attached';
  }

  get size(): LiftSize {
    if (this.args.size) return this.args.size;
    // Per-kind defaults when contract didn't specify.
    if (this.args.kind === 'edit') return 'comfortable';
    if (this.args.kind === 'tools') return 'compact';
    return 'compact'; // details / preview
  }

  get backdrop(): LiftBackdrop {
    if (this.args.backdrop) return this.args.backdrop;
    if (this.args.kind === 'edit') return 'blur';
    if (this.args.kind === 'tools') return 'none';
    return 'tint'; // details / preview
  }

  get elevation(): LiftElevation {
    if (this.args.elevation) return this.args.elevation;
    if (this.placementMode === 'plane') return 'modal';
    if (this.args.kind === 'edit') return 'elevated';
    return 'raised';
  }

  get keyboardModel(): LiftKeyboardModel {
    return this.args.keyboardModel ?? 'compose';
  }

  get isShadow(): boolean {
    return this.placementMode === 'shadow';
  }

  get isPlane(): boolean {
    return this.placementMode === 'plane';
  }

  get hasScrim(): boolean {
    return this.backdrop === 'scrim';
  }

  /** Default autoFocus policy. */
  get shouldAutoFocus(): boolean {
    if (this.args.autoFocus !== undefined) return this.args.autoFocus;
    return this.args.kind !== 'details';
  }

  /** Edit lifts are popover-shaped but modal-like for focus. */
  get shouldTrapFocus(): boolean {
    return this.args.kind === 'edit' || this.placementMode === 'plane';
  }

  get shouldDelegateKeyboard(): boolean {
    return (
      this.args.kind === 'edit' ||
      this.args.kind === 'tools' ||
      this.placementMode === 'plane'
    );
  }

  get layerTier(): SurfaceLayerTier {
    if (this.args.layerTier) return this.args.layerTier;
    if (this.placementMode === 'plane' || this.elevation === 'modal') {
      return 'modal';
    }
    if (this.placementMode === 'shadow') return 'cell-lift';
    return 'popover';
  }

  /** Inline style string for the lift root. Carries the optional
   *  `relativeScale` arg as a `transform: scale(...)` with origin
   *  pinned to the lift's top-left corner.
   *
   *  WHY NOT CSS `zoom`: the CSS `zoom` property scales ALL element
   *  dimensions — INCLUDING positional `top` / `left` written by the
   *  anchored positioning modifier. So a lift with `top: 200px` and
   *  `zoom: 0.8` actually paints at `top: 160px`, jumping it away
   *  from its anchor. That was the "position out of whack" bug.
   *
   *  WHY transform + top-left origin: the anchor modifier uses Floating UI's
   *  `computePosition` which already reads `getBoundingClientRect`
   *  (which RETURNS post-transform coords), so the scaled lift's
   *  apparent box is what the positioner sizes against. With
   *  `transform-origin: top left`, the visual top-left of the scaled
   *  box stays exactly at the `top: y; left: x;` point — for
   *  `bottom-start` placement that's the cell's bottom-left, which
   *  is what we want.
   *
   *  Plane placement gets NO scale (plane is a viewport modal, not
   *  an anchored surface; it always renders at viewport scale). */
  get rootStyle(): string {
    const z = this.args.relativeScale;
    if (z === undefined || z === 1) return '';
    // Only attached lifts honor relativeScale. Plane is a viewport
    // modal — not anchored to scalable host content. Shadow already
    // overlays the source cell which is itself in host coords (the
    // shadowAnchor modifier reads cell's screen bbox, which already
    // reflects canvas zoom), so an extra scale would double-apply.
    if (this.placementMode !== 'attached') return '';
    // Hard safety clamp — the damped curve helper already produces
    // a tight range (0.7..1.5 typical), but a host that does its own
    // math could send something extreme. We don't want layout to
    // explode either way.
    const clamped = Math.max(0.4, Math.min(2.5, z));
    return `transform: scale(${clamped}); transform-origin: top left;`;
  }

  // ─── classes ────────────────────────────────────────────────────

  /** Composite class for the lift root. Includes kind + placement
   *  + size + backdrop + elevation. CSS reads these as orthogonal
   *  modifiers (see styles below). */
  get liftClass(): string {
    return [
      'bx-lift',
      `bx-lift--${this.args.kind}`,
      `bx-lift--placement-${this.placementMode}`,
      `bx-lift--size-${this.size}`,
      `bx-lift--backdrop-${this.backdrop}`,
      `bx-lift--elevation-${this.elevation}`,
    ].join(' ');
  }

  // ─── escalation glyph ──────────────────────────────────────────

  /** Other kinds the user can escalate to (filtered to exclude
   *  the current one). When empty, no escalation chrome renders. */
  get escalationTargets(): LiftKind[] {
    return (this.args.canEscalateTo ?? []).filter((k) => k !== this.args.kind);
  }

  get hasEscalation(): boolean {
    return this.escalationTargets.length > 0 && this.args.onEscalate != null;
  }

  /** Glyph for the corner escalation button. When escalation has
   *  exactly one target, use that target's glyph. Otherwise (rare,
   *  but supported), use a generic kebab. */
  get escalationGlyph(): string {
    const targets = this.escalationTargets;
    const only = targets[0];
    if (targets.length === 1 && only) return this.kindGlyph(only);
    return '⋯';
  }

  /** Aria-label for the corner escalation button. */
  get escalationLabel(): string {
    const targets = this.escalationTargets;
    const only = targets[0];
    if (targets.length === 1 && only) {
      return `Switch to ${this.kindLabel(only)}`;
    }
    return 'Switch lift mode';
  }

  /** Default action when the user clicks the corner glyph. With
   *  exactly one escalation target, fire that. Otherwise rotate
   *  through targets. */
  fireEscalateNext = (): void => {
    const targets = this.escalationTargets;
    const first = targets[0];
    if (targets.length === 0) return;
    if (targets.length === 1 && first) {
      this.args.onEscalate?.(first);
      return;
    }
    // Multi-target — pick the first that ISN'T the current kind.
    if (first) this.args.onEscalate?.(first);
  };

  kindLabel(kind: LiftKind): string {
    switch (kind) {
      case 'details':
        return 'Details';
      case 'preview':
        return 'Preview';
      case 'edit':
        return 'Edit';
      case 'tools':
        return 'Tools';
    }
  }

  kindGlyph(kind: LiftKind): string {
    switch (kind) {
      case 'details':
        return 'ⓘ';
      case 'preview':
        return '⊡';
      case 'edit':
        return '✎';
      case 'tools':
        return '⋯';
    }
  }

  /** Scrim click — fires onDismiss if provided. Bound here so the
   *  template can wire it without `(fn ...)` plumbing. */
  handleScrimClick = (): void => {
    this.args.onDismiss?.();
  };

  // Modifiers exposed on instance for Glint strict mode.
  anchoredLift = anchoredLift;
  shadowAnchor = shadowAnchor;
  liftFocus = liftFocusModifier;
  trapLiftFocus = trapLiftFocusModifier;
  delegateLiftKeyboard = delegateLiftKeyboardModifier;
  dismissOnOutside = dismissOnOutside;
  allocateLiftLayer = allocateLiftLayer;
  liftSurfaceRoot = liftSurfaceRoot;
  cleanupClosedLift = cleanupClosedLiftModifier;

  <template>
    <span
      hidden
      aria-hidden='true'
      {{this.cleanupClosedLift @open this.instanceId}}
    ></span>
    {{#unless @open}}
      <span
        hidden
        aria-hidden='true'
        {{this.cleanupClosedLift false this.instanceId}}
      ></span>
    {{/unless}}
    {{#if @open}}
      {{! Scrim — full-viewport dim layer behind the lift, mounted
            as a sibling so it doesn't share the lift's z-stack. Only
            renders when backdrop === 'scrim' (plane modals).  }}
      {{#if this.hasScrim}}
        {{#in-element this.portalTarget insertBefore=null}}
          <div
            class='bx-lift-scrim'
            data-bx-lift-instance={{this.instanceId}}
            {{on 'click' this.handleScrimClick}}
            {{surfaceScopeRelay this.scopeRelay}}
            aria-hidden='true'
          ></div>
        {{/in-element}}
      {{/if}}

      {{#if this.isShadow}}
        {{#in-element this.portalTarget insertBefore=null}}
          <div
            class={{this.liftClass}}
            data-bx-lift
            data-bx-lift-instance={{this.instanceId}}
            data-bx-lift-kind={{@kind}}
            data-bx-lift-placement='shadow'
            data-bx-lift-anchor-selector={{@anchor}}
            data-bx-lift-keyboard-model={{this.keyboardModel}}
            data-bx-lift-keyboard-lock={{if
              this.shouldDelegateKeyboard
              'true'
              'false'
            }}
            data-bx-lift-focus-token={{@focusToken}}
            data-surface-preserve-focus
            style={{this.rootStyle}}
            {{this.allocateLiftLayer this.layerTier @zIndex}}
            {{this.liftSurfaceRoot
              anchor=@anchor
              ladder=this.inheritedLadder
              runtime=this.inheritedRuntime
              liftManager=this.inheritedLiftManager
              mode=this.inheritedMode
              inspect=this.inheritedInspect
            }}
            {{this.shadowAnchor @anchor}}
            {{this.dismissOnOutside @onDismiss}}
            {{this.liftFocus @focusToken enabled=this.shouldAutoFocus}}
            {{this.trapLiftFocus enabled=this.shouldTrapFocus}}
            {{this.delegateLiftKeyboard enabled=this.shouldDelegateKeyboard}}
            {{surfaceScopeRelay this.scopeRelay}}
            ...attributes
          >
            {{#if this.hasEscalation}}
              <button
                type='button'
                class='bx-lift__escalate'
                aria-label={{this.escalationLabel}}
                title={{this.escalationLabel}}
                {{on 'click' this.fireEscalateNext}}
              >{{this.escalationGlyph}}</button>
            {{/if}}
            <div class='bx-lift__body'>
              {{yield @kind}}
            </div>
          </div>
        {{/in-element}}
      {{else if this.isPlane}}
        {{#in-element this.portalTarget insertBefore=null}}
          <div
            class={{this.liftClass}}
            data-bx-lift
            data-bx-lift-instance={{this.instanceId}}
            data-bx-lift-kind={{@kind}}
            data-bx-lift-placement='plane'
            data-bx-lift-anchor-selector={{@anchor}}
            data-bx-lift-keyboard-model={{this.keyboardModel}}
            data-bx-lift-keyboard-lock={{if
              this.shouldDelegateKeyboard
              'true'
              'false'
            }}
            data-bx-lift-focus-token={{@focusToken}}
            data-surface-preserve-focus
            style={{this.rootStyle}}
            {{this.allocateLiftLayer this.layerTier @zIndex}}
            {{this.liftSurfaceRoot
              anchor=@anchor
              ladder=this.inheritedLadder
              runtime=this.inheritedRuntime
              liftManager=this.inheritedLiftManager
              mode=this.inheritedMode
              inspect=this.inheritedInspect
            }}
            {{this.dismissOnOutside @onDismiss}}
            {{this.liftFocus @focusToken enabled=this.shouldAutoFocus}}
            {{this.trapLiftFocus enabled=this.shouldTrapFocus}}
            {{this.delegateLiftKeyboard enabled=this.shouldDelegateKeyboard}}
            {{surfaceScopeRelay this.scopeRelay}}
            ...attributes
          >
            {{#if this.hasEscalation}}
              <button
                type='button'
                class='bx-lift__escalate'
                aria-label={{this.escalationLabel}}
                title={{this.escalationLabel}}
                {{on 'click' this.fireEscalateNext}}
              >{{this.escalationGlyph}}</button>
            {{/if}}
            <div class='bx-lift__body'>
              {{yield @kind}}
            </div>
          </div>
        {{/in-element}}
      {{else}}
        {{#in-element this.portalTarget insertBefore=null}}
          <div
            class={{this.liftClass}}
            data-bx-lift
            data-bx-lift-instance={{this.instanceId}}
            data-bx-lift-kind={{@kind}}
            data-bx-lift-placement='attached'
            data-bx-lift-anchor-selector={{@anchor}}
            data-bx-lift-keyboard-model={{this.keyboardModel}}
            data-bx-lift-keyboard-lock={{if
              this.shouldDelegateKeyboard
              'true'
              'false'
            }}
            data-bx-lift-focus-token={{@focusToken}}
            data-surface-preserve-focus
            style={{this.rootStyle}}
            {{this.allocateLiftLayer this.layerTier @zIndex}}
            {{this.liftSurfaceRoot
              anchor=@anchor
              ladder=this.inheritedLadder
              runtime=this.inheritedRuntime
              liftManager=this.inheritedLiftManager
              mode=this.inheritedMode
              inspect=this.inheritedInspect
            }}
            {{this.anchoredLift
              @anchor
              placement=this.effectivePlacement
              offsetOptions=8
            }}
            {{this.dismissOnOutside @onDismiss}}
            {{this.liftFocus @focusToken enabled=this.shouldAutoFocus}}
            {{this.trapLiftFocus enabled=this.shouldTrapFocus}}
            {{this.delegateLiftKeyboard enabled=this.shouldDelegateKeyboard}}
            {{surfaceScopeRelay this.scopeRelay}}
            ...attributes
          >
            {{#if this.hasEscalation}}
              <button
                type='button'
                class='bx-lift__escalate'
                aria-label={{this.escalationLabel}}
                title={{this.escalationLabel}}
                {{on 'click' this.fireEscalateNext}}
              >{{this.escalationGlyph}}</button>
            {{/if}}
            <div class='bx-lift__body'>
              {{yield @kind}}
            </div>
          </div>
        {{/in-element}}
      {{/if}}
    {{/if}}

    <style scoped>
      /* ════════════════════════════════════════════════════════════
       * Lift visual system — driven by 5 orthogonal class modifiers:
       *   .bx-lift--{kind}        details | preview | edit | tools
       *   .bx-lift--placement-{p} attached | shadow | plane
       *   .bx-lift--size-{s}      compact | comfortable | spacious | auto
       *   .bx-lift--backdrop-{b}  none | tint | blur | scrim
       *   .bx-lift--elevation-{e} flat | raised | elevated | modal
       *
       * Each axis paints ONE thing, so the cartesian product is
       * predictable. CSS custom properties let hosts re-skin
       * without overriding rules.
       * ════════════════════════════════════════════════════════════ */

      .bx-lift {
        position: absolute;
        z-index: var(--bx-lift-z, 1000);
        font:
          13px/1.4 Inter,
          ui-sans-serif,
          system-ui,
          -apple-system,
          Segoe UI,
          sans-serif;
        color: var(--bx-lift-fg, #111827);
        /* overflow hidden clips children to the lift's
         * border-radius. Without this, an inner scroll container
         * (.bx-lift__body with overflow auto) paints over the
         * rounded corners — visible as a square notch in the bottom
         * corners of any picker / list. The corner-escalation glyph
         * sits inside the radius (top: 6px right: 6px) so it isn't
         * affected. Box-shadow is OUTSIDE the content box and stays
         * unclipped (the elevation ring still paints around the
         * rounded edge). */
        overflow: hidden;
        animation: bx-lift-in 100ms cubic-bezier(0.32, 0.72, 0.4, 1);
      }
      @keyframes bx-lift-in {
        from {
          opacity: 0;
          transform: translateY(-2px) scale(0.985);
        }
        to {
          opacity: 1;
          transform: translateY(0) scale(1);
        }
      }

      /* ─── SIZE — width / height tokens ─────────────────────────
       * "Comb" pass: prior defaults were too generous, popovers felt
       * ceremonious. New defaults hug the content. Each tier's
       * MAX-width is the smallest box that fits its target use case
       * cleanly; min-width is just below that so picker rows don't
       * shrink under their content. Hosts override per-token via
       * CSS custom properties.
       *
       *   compact     status pill picker, true/false picker (~6-8 word menus)
       *   comfortable date picker grid, chips picker, slider editor
       *   spacious    formula builder, color picker grid, year-12-grid
       */
      .bx-lift--size-compact {
        min-width: var(--bx-lift-size-compact-min-w, 176px);
        max-width: min(var(--bx-lift-size-compact-max-w, 240px), 92vw);
        max-height: min(var(--bx-lift-size-compact-max-h, 280px), 75vh);
      }
      .bx-lift--size-comfortable {
        min-width: var(--bx-lift-size-comfortable-min-w, 240px);
        max-width: min(var(--bx-lift-size-comfortable-max-w, 320px), 92vw);
        max-height: min(var(--bx-lift-size-comfortable-max-h, 360px), 75vh);
      }
      .bx-lift--size-spacious {
        min-width: var(--bx-lift-size-spacious-min-w, 320px);
        max-width: min(var(--bx-lift-size-spacious-max-w, 460px), 92vw);
        max-height: min(var(--bx-lift-size-spacious-max-h, 500px), 80vh);
      }
      /* auto adds nothing — content drives. Used for shadow lifts
       * where the anchor's width is the floor (set by shadowAnchor). */

      /* ─── BACKDROP — visual separation ────────────────────────── */
      .bx-lift--backdrop-none {
        background: var(--bx-lift-bg, #fff);
      }
      .bx-lift--backdrop-tint {
        background: rgba(255, 255, 255, 0.98);
      }
      .bx-lift--backdrop-blur {
        background: var(--bx-lift-bg, #fff);
        backdrop-filter: blur(6px);
        -webkit-backdrop-filter: blur(6px);
      }
      .bx-lift--backdrop-scrim {
        background: var(--bx-lift-bg, #fff);
      }

      /* Scrim — full-viewport dim layer mounted as a sibling.
       * Click dismisses (host wires onDismiss). Z-index sits ONE
       * BELOW the lift's z (so the lift renders on top). */
      .bx-lift-scrim {
        position: fixed;
        inset: 0;
        background: var(--bx-lift-scrim-bg, rgba(15, 23, 42, 0.4));
        backdrop-filter: blur(2px);
        z-index: calc(var(--bx-lift-z, 10000) - 1);
        animation: bx-lift-scrim-in 140ms ease-out;
      }
      @keyframes bx-lift-scrim-in {
        from {
          opacity: 0;
        }
        to {
          opacity: 1;
        }
      }

      /* ─── ELEVATION — shadow + ring ladder ─────────────────────
       * Numbers from lift-panel mockup §5. Each tier ONE notch up:
       *   radius      4 → 6 → 8 → 12
       *   shadow      flat → raised → elevated → modal
       *   accent ring none → none → 1px @ 32% → 1px @ 18%
       * Ring SHRINKS in opacity as elevation grows — the deeper
       * shadow takes over the "lifted" job. */
      .bx-lift--elevation-flat {
        box-shadow: var(--bx-lift-shadow-flat, 0 1px 2px rgba(0, 0, 0, 0.06));
        border-radius: 4px;
      }
      .bx-lift--elevation-raised {
        box-shadow: var(
          --bx-lift-shadow-raised,
          0 2px 6px -1px rgba(0, 0, 0, 0.08),
          0 1px 2px rgba(0, 0, 0, 0.04)
        );
        border: 1px solid var(--bx-lift-border-soft, #e5e7eb);
        border-radius: 6px;
      }
      .bx-lift--elevation-elevated {
        box-shadow: var(
          --bx-lift-shadow-elevated,
          0 8px 16px -4px rgba(15, 23, 42, 0.1),
          0 2px 4px -2px rgba(15, 23, 42, 0.06),
          0 0 0 1px
            color-mix(in srgb, var(--bx-lift-accent, #4f46e5) 32%, transparent)
        );
        border-radius: 8px;
      }
      .bx-lift--elevation-modal {
        --bx-lift-z: 10000;
        box-shadow: var(
          --bx-lift-shadow-modal,
          0 32px 56px -16px rgba(15, 23, 42, 0.22),
          0 12px 24px -8px rgba(15, 23, 42, 0.14),
          0 0 0 1px
            color-mix(in srgb, var(--bx-lift-accent, #4f46e5) 18%, transparent)
        );
        border-radius: 12px;
      }

      /* ─── PLACEMENT — geometry tweaks ─────────────────────────── */
      .bx-lift--placement-shadow {
        /* Shadow lift OVERLAYS the source cell. Per mockup §3:
         *   - tighter 4px radius (matches cell, "the cell grew")
         *   - small downward shadow + accent ring (1.5px) only;
         *     no large drop shadow extending below the row. */
        border-radius: 4px;
        box-shadow:
          0 4px 8px -2px rgba(15, 23, 42, 0.1),
          0 0 0 1.5px var(--bx-lift-accent, #4f46e5);
      }
      .bx-lift--placement-plane {
        position: fixed;
        top: 50%;
        left: 50%;
        transform: translate(-50%, -50%);
        animation: bx-lift-plane-in 180ms cubic-bezier(0.32, 0.72, 0.4, 1);
      }
      @keyframes bx-lift-plane-in {
        from {
          opacity: 0;
          transform: translate(-50%, -48%) scale(0.96);
        }
        to {
          opacity: 1;
          transform: translate(-50%, -50%) scale(1);
        }
      }

      /* ─── KIND — content-color hints ──────────────────────────
       * Tone-of-voice differentiation. Most chrome is now driven by
       * elevation + size; per-kind overrides only differentiate
       * what's left (tools is dark; details has muted body color). */
      .bx-lift--details {
        color: var(--bx-lift-fg-muted, #1f2937);
        font-size: 12px;
      }
      .bx-lift--tools {
        background: var(--bx-lift-tools-bg, #1f2937);
        color: var(--bx-lift-tools-fg, #f9fafb);
      }
      .bx-lift--edit {
        --bx-lift-edit-bg: #fef7d6;
        --bx-lift-edit-border: #f5d75e;
        background: var(--bx-lift-edit-bg);
      }
      .bx-lift--edit .bx-lift__body > [data-surface-lift-target='edit'] {
        background: var(--bx-lift-edit-bg);
      }
      .bx-lift--edit .bx-lift__body > [data-surface-lift-target='edit'] > * {
        background-color: var(--bx-lift-edit-bg);
        box-shadow:
          inset 0 0 0 1px
            color-mix(in srgb, var(--bx-lift-edit-border) 56%, transparent),
          0 16px 42px rgba(120, 85, 0, 0.12);
      }
      .bx-lift--tools.bx-lift--elevation-raised {
        border-color: rgba(255, 255, 255, 0.08);
      }

      /* ─── ESCALATION GLYPH — corner button ─────────────────────
       * Compact one-glyph escalation in the top-right. Only renders
       * when the contract has multiple lift kinds (the host's
       * canEscalateTo includes kinds OTHER than current. For
       * single-kind contracts, no chrome — the body is the lift. */
      .bx-lift__escalate {
        /* Per mockup §2 — small unobtrusive corner glyph. 18px,
         * always visible at 0.55 opacity (the lift is open, the
         * affordance should be discoverable without hovering),
         * fills with soft accent on hover. */
        position: absolute;
        top: 6px;
        right: 6px;
        z-index: 2;
        width: 18px;
        height: 18px;
        border: none;
        border-radius: 4px;
        background: transparent;
        color: var(--bx-lift-fg-muted, #9ca3af);
        font-size: 12px;
        line-height: 1;
        cursor: pointer;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        transition:
          background 80ms,
          color 80ms,
          opacity 80ms;
        opacity: 0.55;
      }
      .bx-lift__escalate:hover,
      .bx-lift__escalate:focus-visible {
        opacity: 1;
        background: color-mix(
          in srgb,
          var(--bx-lift-accent, #4f46e5) 10%,
          transparent
        );
        color: var(--bx-lift-accent, #4f46e5);
      }
      .bx-lift--tools .bx-lift__escalate {
        color: rgba(255, 255, 255, 0.6);
      }
      .bx-lift--tools .bx-lift__escalate:hover {
        background: rgba(255, 255, 255, 0.12);
        color: #fff;
      }

      /* ─── BODY ──────────────────────────────────────────────────
       *
       * INTENTIONALLY NO PADDING. Each editor mounted inside the
       * lift body owns its own 6px gutter (the "picker convention"):
       *
       *   .pick-many       padding: 6px
       *   .pick-one        padding: 6px
       *   .toggle-strict   padding: 6px
       *   .actions-pane    padding: 6px
       *   .textarea-pane   padding: 6px
       *   .slider--editing padding: 6px
       *   .number-pane     padding: 12px (variant)
       *
       * Why convention vs lift-pads-everything: the picker primitives
       * (PickOne / PickMany) ship as standalone widgets and may be
       * mounted in a Form, an inspector pane, or a custom shell.
       * If the lift OWNED the padding, the picker would have no
       * breathing room outside a lift. Convention keeps each editor
       * self-contained.
       *
       * If you're authoring a new editor pane, add padding: 6px to
       * the root and use gap for inner rhythm. That's it. */
      .bx-lift__body {
        display: block;
        max-height: inherit;
        overflow: auto;
      }
    </style>
  </template>
}
