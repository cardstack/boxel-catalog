// Pretui — Dialog: a modal on the native <dialog> top layer.
import Component from '@glimmer/component';
import { emit, resolveSize } from '../pretui-primitives';
import type { PretuiSizeArg } from '../pretui-primitives';
import { provide } from 'ember-provide-consume-context';
import {
  POPUPS_IN_PLACE,
  resolveOpen,
  modalBehavior,
} from '../internal/overlay';
import type { OpenArgs } from '../internal/overlay';

/** The three width steps a Dialog paints, and every spelling of them. */
type DialogSize = 's' | 'm' | 'l';
const DIALOG_SIZES: Record<string, DialogSize> = {
  xs: 's',
  s: 's',
  m: 'm',
  l: 'l',
  xl: 'l',
};

export interface DialogSignature {
  Args: OpenArgs & {
    /** Canonical close notify. Optional since 2026-08-13: a caller who only
     * passes `@onOpenChange` (the Radix/shadcn contract, and what an agent
     * will type) used to hit a hard `this.args.onClose is not a function`. */
    onClose?: () => void;
    /** alias — the Radix/shadcn layer notify, called with `false` on close.
     * A layer needs a two-way knob: `@onClose` alone cannot reopen it. */
    onOpenChange?: (open: boolean) => void;
    label?: string;
    /** the `s|m|l` width steps; `sm`/`md`/`lg`/`default` accepted */
    size?: DialogSize | PretuiSizeArg;
    dismissible?: boolean;
  };
  Blocks: { title: []; default: []; footer: [] };
  Element: HTMLDialogElement;
}

export class Dialog extends Component<DialogSignature> {
  @provide(POPUPS_IN_PLACE)
  get popupsInPlace() {
    return true;
  }
  get dismissible() {
    return this.args.dismissible ?? true;
  }
  get open() {
    return resolveOpen(this.args);
  }
  get size(): DialogSize {
    return DIALOG_SIZES[resolveSize(this.args.size)] ?? 'm';
  }
  private requestClose() {
    emit([this.args.onClose]);
    emit([this.args.onOpenChange], false);
  }
  onCancel = (e: Event) => {
    // Escape. Keep the element controlled: never let the platform close it
    // out from under the @open arg.
    e.preventDefault();
    if (this.dismissible) {
      this.requestClose();
    }
  };
  onClick = (e: Event) => {
    // The inner wrapper covers the whole dialog, so a click that targets the
    // <dialog> itself landed on the ::backdrop.
    if (this.dismissible && e.target === e.currentTarget) {
      this.requestClose();
    }
  };
  <template>
    <dialog
      class='pretui-dialog'
      data-size={{this.size}}
      aria-label={{@label}}
      data-test-pretui-dialog
      {{modalBehavior this.open this.onCancel this.onClick}}
      ...attributes
    >
      <div class='pretui-dialog-inner'>
        {{#if (has-block 'title')}}
          <header class='pretui-dialog-title'>{{yield to='title'}}</header>
        {{/if}}
        <div class='pretui-dialog-body'>{{yield}}</div>
        {{#if (has-block 'footer')}}
          <footer class='pretui-dialog-footer'>{{yield to='footer'}}</footer>
        {{/if}}
      </div>
    </dialog>
    <style scoped>
      @layer PretComponent {
        .pretui-dialog {
          border: 0;
          padding: 0;
          background: var(--card);
          color: var(--foreground);
          border-radius: var(--boxel-border-radius);
          box-shadow: var(
            --pretui-shadow-overlay,
            0 0 0 1px var(--border),
            var(--shadow-xl)
          );
          width: min(35rem, calc(100vw - 2rem));
          max-height: calc(100dvh - 4rem);
          font-size: var(--boxel-body-font-size);
        }
        .pretui-dialog[data-size='s'] {
          width: min(25rem, calc(100vw - 2rem));
        }
        .pretui-dialog[data-size='l'] {
          width: min(47.5rem, calc(100vw - 2rem));
        }
        .pretui-dialog::backdrop {
          background: var(--pretui-overlay-scrim, var(--overlay));
        }
        .pretui-dialog[open] {
          opacity: 1;
          transform: none;
          transition:
            opacity 200ms cubic-bezier(0.23, 1, 0.32, 1),
            transform 200ms cubic-bezier(0.23, 1, 0.32, 1);
        }
        @starting-style {
          .pretui-dialog[open] {
            opacity: 0;
            transform: translateY(0.375rem) scale(0.98);
          }
        }
        .pretui-dialog-inner {
          display: grid;
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp);
        }
        .pretui-dialog-title {
          font-size: var(--boxel-font-size);
          font-weight: 600;
          letter-spacing: normal;
        }
        .pretui-dialog-body {
          color: var(--muted-foreground);
        }
        .pretui-dialog-footer {
          display: flex;
          justify-content: flex-end;
          gap: var(--boxel-sp-xs);
          border-top: 1px solid var(--border);
          padding-top: var(--boxel-sp-sm);
        }
        @media (prefers-reduced-motion: reduce) {
          .pretui-dialog[open] {
            transition: none;
          }
        }
      }
    </style>
  </template>
}
