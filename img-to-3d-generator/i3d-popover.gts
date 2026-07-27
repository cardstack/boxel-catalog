import Component from '@glimmer/component';
import { on } from '@ember/modifier';
import { htmlSafe, type SafeString } from '@ember/template';
import Popover from '../46f065-popover/popover';
import type { Placement } from '@floating-ui/dom';

type PopKind = 'details' | 'edit' | 'tools';
type PopAnchoring = 'beside' | 'overlay' | 'center';
type PopSize = 'compact' | 'comfortable' | 'spacious' | 'auto';
type PopBackdrop = 'none' | 'tint' | 'blur' | 'dim';
type PopElevation = 'flat' | 'raised' | 'elevated' | 'floating';

interface Signature {
  Element: HTMLDivElement;
  Args: {
    /** CSS selector the popover velcros to. */
    anchor: string;
    /** Called on Esc / outside-click AND the header ✕ button. */
    onClose: () => void;
    /** Header title — shown when no `:header` block is provided. */
    title?: string;
    /** Small uppercase kicker above the title (default header only). */
    kicker?: string;
    /** When false the popover is unmounted. Default true. */
    open?: boolean;
    /** Extra class on the shell root for per-popover tweaks. */
    class?: string;
    /* ---- Popover positioning pass-through (sensible defaults) ---- */
    kind?: PopKind;
    anchoring?: PopAnchoring;
    placement?: Placement;
    size?: PopSize;
    backdrop?: PopBackdrop;
    elevation?: PopElevation;
    /** Gap in px between the anchor and the popover. */
    offset?: number;
    /** Accessible label for the popover surface. Falls back to `title`. */
    label?: string;
  };
  Blocks: {
    /** Custom header content. The ✕ close button is always appended by
     *  the shell. Omit to get the default title/kicker header. */
    header: [];
    /** The scrollable body — the popover's main content. */
    body: [];
    /** Optional pinned footer (actions that shouldn't scroll away). */
    foot: [];
  };
}

/**
 * `<ImgTo3dPopover>` — the shared popover shell for the img-to-3d studio.
 * Wraps the catalog `<Popover>` (which owns floating-ui positioning and
 * Esc / outside-click dismissal) but paints its OWN deep-space dark surface
 * over the catalog chrome, so it never shows the light default. Provides a
 * sticky header (title/kicker or a custom `:header`, plus a ✕ close), a
 * scrollable `:body`, and an optional pinned `:foot`.
 *
 * The catalog Popover portals content out of the card's theme scope, so the
 * shell re-declares the `--_*` private aliases the studio's content uses —
 * yielded `.history-*` / `.inpaint-*` elements keep their host scoped-CSS
 * classes AND resolve the same tokens they do inside `.studio`.
 */
export default class ImgTo3dPopover extends Component<Signature> {
  get open() {
    return this.args.open ?? true;
  }

  get kind(): PopKind {
    return this.args.kind ?? 'tools';
  }

  get anchoring(): PopAnchoring {
    return this.args.anchoring ?? 'beside';
  }

  get placement(): Placement {
    return this.args.placement ?? 'bottom-end';
  }

  get size(): PopSize {
    return this.args.size ?? 'auto';
  }

  get backdrop(): PopBackdrop {
    return this.args.backdrop ?? 'none';
  }

  get elevation(): PopElevation {
    return this.args.elevation ?? 'floating';
  }

  get label() {
    return this.args.label ?? this.args.title ?? 'Panel';
  }

  // The rounded chrome you see is the catalog Popover's own surface, not this
  // shell — and at elevation 'floating' it computes `--bx-popover-radius * 2`,
  // which is why setting a small radius on .i3d-pop alone changed nothing.
  // Popover spreads ...attributes onto that surface, so the variable can be set
  // from here: 3px doubles to a 6px corner, and the floating shadow is kept.
  get shellStyle(): SafeString {
    return htmlSafe('--bx-popover-radius: 3px;');
  }

  <template>
    <Popover
      @anchor={{@anchor}}
      @open={{this.open}}
      @kind={{this.kind}}
      @anchoring={{this.anchoring}}
      @placement={{this.placement}}
      @size={{this.size}}
      @backdrop={{this.backdrop}}
      @elevation={{this.elevation}}
      @offset={{@offset}}
      @label={{this.label}}
      @onDismiss={{@onClose}}
      style={{this.shellStyle}}
    >
      <:tools>
        <div class='i3d-pop {{@class}}' ...attributes>
          <div class='i3d-pop-head'>
            {{#if (has-block 'header')}}
              {{yield to='header'}}
            {{else}}
              <div class='i3d-pop-titles'>
                {{#if @kicker}}
                  <div class='i3d-pop-kicker'>{{@kicker}}</div>
                {{/if}}
                <div class='i3d-pop-title'>{{@title}}</div>
              </div>
            {{/if}}
            <button
              type='button'
              class='i3d-pop-close'
              aria-label='Close'
              {{on 'click' @onClose}}
            >✕</button>
          </div>
          <div class='i3d-pop-body'>
            {{yield to='body'}}
          </div>
          {{#if (has-block 'foot')}}
            <div class='i3d-pop-foot'>{{yield to='foot'}}</div>
          {{/if}}
        </div>
      </:tools>
    </Popover>

    <style scoped>
      .i3d-pop {
        /* re-declare the studio's private aliases (portaled out of .studio) */
        --_bg: var(--i3d-bg, var(--background, #0a0b10));
        --_surface: var(--i3d-surface, var(--card, #14161e));
        --_border: var(--i3d-border, var(--border, #232838));
        --_text: var(--i3d-text, var(--foreground, #eef0f6));
        --_dim: var(--i3d-text-dim, var(--muted-foreground, #9aa0b2));
        --_accent: var(--i3d-accent, var(--accent, #38e8ff));
        --_mono: var(
          --i3d-font-mono,
          var(--font-mono, ui-monospace, 'SFMono-Regular', Menlo, monospace)
        );
        /* one radius for the shell and everything docked to its edges — a
           tool panel reads as an instrument, not a card, so it stays tight */
        --_pop-radius: 0.25rem;
        position: relative;
        display: flex;
        flex-direction: column;
        max-height: min(70vh, calc(100vh - 48px));
        max-width: min(40rem, 85vw);
        border-radius: var(--_pop-radius);
        overflow: hidden;
        background: var(--_surface);
        color: var(--_text);
        font-family: var(--_mono);
      }
      .i3d-pop-head {
        position: sticky;
        top: 0;
        z-index: 2;
        flex: none;
        display: flex;
        align-items: center;
        gap: 0.375rem;
        padding: 0.4375rem 0.4375rem 0.4375rem 0.625rem;
        background: var(--_surface);
        border-bottom: 1px solid var(--_border);
      }
      .i3d-pop-titles {
        flex: 1;
        min-width: 0;
        /* kicker and title sit on one baseline row when both are present, so
           the header stays a single line tall */
        display: flex;
        align-items: baseline;
        gap: 0.4375rem;
        overflow: hidden;
      }
      .i3d-pop-kicker {
        flex: none;
        font-size: 0.5rem;
        font-weight: 600;
        letter-spacing: 0.16em;
        text-transform: uppercase;
        color: var(--_accent);
      }
      .i3d-pop-title {
        font-size: 0.6875rem;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        color: var(--_text);
      }
      .i3d-pop-close {
        flex: none;
        display: flex;
        align-items: center;
        justify-content: center;
        /* a small square target: a circle at this size reads as a bubble and
           fights the squared-off shell */
        width: 1.125rem;
        height: 1.125rem;
        border-radius: 0.1875rem;
        border: 1px solid var(--_border);
        background: transparent;
        color: var(--_dim);
        font-size: 0.5625rem;
        line-height: 1;
        cursor: pointer;
        transition: 0.15s;
      }
      .i3d-pop-close:hover {
        border-color: var(--_accent);
        color: var(--_accent);
        background: color-mix(in srgb, var(--_accent) 12%, transparent);
      }
      .i3d-pop-close:focus-visible {
        outline: 1px solid var(--_accent);
        outline-offset: 1px;
      }
      .i3d-pop-body {
        position: relative;
        flex: 1;
        min-height: 0;
        overflow-y: auto;
        padding: 0.625rem;
      }
      .i3d-pop-foot {
        flex: none;
        padding: 0.5rem 0.625rem;
        border-top: 1px solid var(--_border);
      }
    </style>
  </template>
}
