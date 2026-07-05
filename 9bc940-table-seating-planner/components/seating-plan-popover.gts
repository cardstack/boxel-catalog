import Component from '@glimmer/component';
import { on } from '@ember/modifier';
import type { SafeString } from '@ember/template';
import Popover from '@cardstack/catalog/46f065-popover/popover';
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
    /** Fixed shell width in px. Default 264. */
    width?: number;
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
    /** Custom header content (e.g. an editable name + toggle). The ✕
     *  close button is always appended by the shell. Omit to get the
     *  default title/kicker header. */
    header: [];
    /** The scrollable body — the popover's main content. */
    body: [];
    /** Optional pinned footer (actions that shouldn't scroll away). */
    foot: [];
  };
}

/**
 * `<SeatingPlanPopover>` — the one popover shell every Table Seating
 * Planner popover shares: a themed dark surface with a sticky header
 * (title/kicker or a custom `:header`, plus a ✕ close), a scrollable
 * `:body` that caps its height and never runs off-screen, and an
 * optional pinned `:foot`. It wraps the catalog `<Popover>` and owns
 * positioning defaults so call sites only pass an anchor + onClose.
 *
 * Body/header/foot content is yielded from the host, so those elements
 * keep the host's scoped-CSS classes — this component only owns the
 * shell chrome (glow, header bar, scroll container).
 */
export default class SeatingPlanPopover extends Component<Signature> {
  get open() {
    return this.args.open ?? true;
  }
  get kind(): PopKind {
    return this.args.kind ?? 'edit';
  }
  get anchoring(): PopAnchoring {
    return this.args.anchoring ?? 'beside';
  }
  get placement(): Placement {
    return this.args.placement ?? 'right-start';
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
    return this.args.label ?? this.args.title ?? 'Edit';
  }
  get widthStyle(): SafeString | string {
    let w = this.args.width ?? 264;
    return `width:${w}px;`;
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
    >

      <:edit>
        <div class='spp {{@class}}' style={{this.widthStyle}} ...attributes>
          <div class='spp-glow'></div>
          <div class='spp-head'>
            {{#if (has-block 'header')}}
              {{yield to='header'}}
            {{else}}
              <div class='spp-titles'>
                {{#if @kicker}}<div class='spp-kicker'>{{@kicker}}</div>{{/if}}
                <div class='spp-title'>{{@title}}</div>
              </div>
            {{/if}}
            <button
              type='button'
              class='spp-close'
              aria-label='Close'
              {{on 'click' @onClose}}
            >✕</button>
          </div>
          <div class='spp-body'>
            {{yield to='body'}}
          </div>
          {{#if (has-block 'foot')}}
            <div class='spp-foot'>{{yield to='foot'}}</div>
          {{/if}}
        </div>
      </:edit>

      <:details>
        <div class='spp {{@class}}' style={{this.widthStyle}} ...attributes>
          <div class='spp-glow'></div>
          <div class='spp-head'>
            {{#if (has-block 'header')}}
              {{yield to='header'}}
            {{else}}
              <div class='spp-titles'>
                {{#if @kicker}}<div class='spp-kicker'>{{@kicker}}</div>{{/if}}
                <div class='spp-title'>{{@title}}</div>
              </div>
            {{/if}}
            <button
              type='button'
              class='spp-close'
              aria-label='Close'
              {{on 'click' @onClose}}
            >✕</button>
          </div>
          <div class='spp-body'>
            {{yield to='body'}}
          </div>
          {{#if (has-block 'foot')}}
            <div class='spp-foot'>{{yield to='foot'}}</div>
          {{/if}}
        </div>
      </:details>
    </Popover>

    <style scoped>
      @import url('https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,400..700;1,400..700&family=Jost:ital,wght@0,300..600;1,300..600&display=swap');
      .spp {
        position: relative;
        display: flex;
        flex-direction: column;
        max-height: min(480px, calc(100vh - 48px));
        background: #fdfaf2;
        color: #22283f;
        font-family: 'Jost', system-ui, sans-serif;
        overflow: hidden;
      }
      .spp-glow {
        position: absolute;
        inset: -40% -20% auto -20%;
        height: 150px;
        background:
          radial-gradient(
            60% 90% at 30% 0%,
            rgba(197, 163, 92, 0.35),
            transparent 70%
          ),
          radial-gradient(
            60% 90% at 100% 0%,
            rgba(230, 207, 154, 0.2),
            transparent 70%
          );
        pointer-events: none;
      }
      .spp-head {
        position: sticky;
        top: 0;
        z-index: 2;
        flex: none;
        display: flex;
        align-items: flex-start;
        gap: 8px;
        padding: 16px 16px 12px;
        background: linear-gradient(168deg, #141b33, #1a2238);
        border-bottom: 1px solid rgba(197, 163, 92, 0.25);
      }
      .spp-titles {
        flex: 1;
        min-width: 0;
      }
      .spp-kicker {
        font-family: 'Jost', system-ui, sans-serif;
        font-size: 9.5px;
        font-weight: 500;
        letter-spacing: 0.3em;
        text-transform: uppercase;
        color: #c5a35c;
      }
      .spp-title {
        font-family: 'Cormorant Garamond', Georgia, serif;
        font-size: 22px;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .spp-head .spp-title {
        color: #f3ead6;
      }
      .spp-close {
        flex: none;
        display: flex;
        align-items: center;
        justify-content: center;
        width: 30px;
        height: 30px;
        border-radius: 50%;
        border: 1px solid rgba(255, 255, 255, 0.14);
        background: rgba(255, 255, 255, 0.05);
        color: #f3ead6;
        font-size: 12px;
        line-height: 1;
        cursor: pointer;
        transition: 0.15s;
      }
      .spp-close:hover {
        border-color: #c5a35c;
        color: #c5a35c;
      }
      .spp-body {
        position: relative;
        flex: 1;
        min-height: 0;
        overflow-y: auto;
        padding: 4px 18px 18px;
      }
      .spp-foot {
        flex: none;
        padding: 12px 18px;
        border-top: 1px solid rgba(197, 163, 92, 0.25);
        background: #f4eddb;
      }
    </style>
  </template>
}
