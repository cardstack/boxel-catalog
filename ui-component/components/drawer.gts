// Pretui — Drawer: a slide-over panel on the native <dialog> top layer.
import Component from '@glimmer/component';
import { emit } from '../pretui-primitives';
import { provide } from 'ember-provide-consume-context';
import {
  POPUPS_IN_PLACE,
  resolveDrawerPlacement,
  resolveOpen,
  modalBehavior,
} from '../internal/overlay';
import type {
  PlacementArgs,
  DrawerPlacement,
  OpenArgs,
} from '../internal/overlay';

// An agent asking for a "Sheet" means THIS component (shadcn's Sheet is a
// slide-over; Pretui's Sheet is a spreadsheet grid). Vaul and shadcn spell
// the edge `direction='right'`, Mantine `position='right'`, Radix `side`;
// all three land on the logical `@placement` here — `right` → `end`.
export interface DrawerSignature {
  Args: OpenArgs &
    PlacementArgs & {
      /** Canonical close notify — optional, see Dialog. */
      onClose?: () => void;
      /** alias — the Radix/shadcn layer notify, called with `false` */
      onOpenChange?: (open: boolean) => void;
      label?: string;
      placement?: DrawerPlacement | string;
      dismissible?: boolean;
    };
  Blocks: { title: []; default: []; footer: [] };
  Element: HTMLDialogElement;
}

export class Drawer extends Component<DrawerSignature> {
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
  get placement(): DrawerPlacement {
    return resolveDrawerPlacement(this.args);
  }
  private requestClose() {
    emit([this.args.onClose]);
    emit([this.args.onOpenChange], false);
  }
  onCancel = (e: Event) => {
    e.preventDefault();
    if (this.dismissible) {
      this.requestClose();
    }
  };
  onClick = (e: Event) => {
    if (this.dismissible && e.target === e.currentTarget) {
      this.requestClose();
    }
  };
  <template>
    <dialog
      class='pretui-drawer'
      data-placement={{this.placement}}
      aria-label={{@label}}
      data-test-pretui-drawer
      {{modalBehavior this.open this.onCancel this.onClick}}
      ...attributes
    >
      <div class='pretui-drawer-inner'>
        {{#if (has-block 'title')}}
          <header class='pretui-drawer-title'>{{yield to='title'}}</header>
        {{/if}}
        <div class='pretui-drawer-body'>{{yield}}</div>
        {{#if (has-block 'footer')}}
          <footer class='pretui-drawer-footer'>{{yield to='footer'}}</footer>
        {{/if}}
      </div>
    </dialog>
    <style scoped>
      @layer PretComponent {
        .pretui-drawer {
          border: 0;
          padding: 0;
          background: var(--card);
          color: var(--foreground);
          box-shadow: var(
            --pretui-shadow-overlay,
            0 0 0 1px var(--border),
            var(--shadow-xl)
          );
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-sm);
          max-width: none;
          max-height: none;
        }
        .pretui-drawer[data-placement='end'],
        .pretui-drawer[data-placement='start'] {
          width: min(var(--pretui-drawer-size, 22.5rem), calc(100vw - 3rem));
          height: 100dvh;
          margin-block: 0;
        }
        .pretui-drawer[data-placement='end'] {
          margin-inline: auto 0;
          border-radius: var(--boxel-border-radius) 0 0
            var(--boxel-border-radius);
        }
        .pretui-drawer[data-placement='start'] {
          margin-inline: 0 auto;
          border-radius: 0 var(--boxel-border-radius) var(--boxel-border-radius)
            0;
        }
        .pretui-drawer[data-placement='bottom'] {
          width: 100vw;
          margin: auto 0 0;
          max-height: min(var(--pretui-drawer-size, 26.25rem), 80dvh);
          border-radius: var(--boxel-border-radius) var(--boxel-border-radius) 0
            0;
        }
        .pretui-drawer::backdrop {
          background: var(
            --pretui-overlay-scrim,
            color-mix(in oklch, black 40%, transparent)
          );
        }
        .pretui-drawer[open] {
          opacity: 1;
          transform: none;
          transition:
            opacity 220ms cubic-bezier(0.23, 1, 0.32, 1),
            transform 220ms cubic-bezier(0.23, 1, 0.32, 1);
        }
        @starting-style {
          .pretui-drawer[open][data-placement='end'] {
            opacity: 0;
            transform: translateX(1.5rem);
          }
          .pretui-drawer[open][data-placement='start'] {
            opacity: 0;
            transform: translateX(-1.5rem);
          }
          .pretui-drawer[open][data-placement='bottom'] {
            opacity: 0;
            transform: translateY(1.5rem);
          }
        }
        .pretui-drawer-inner {
          display: grid;
          grid-template-rows: auto 1fr auto;
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp);
          height: 100%;
          box-sizing: border-box;
          align-content: start;
        }
        .pretui-drawer-title {
          font-size: var(--boxel-font-size);
          font-weight: 600;
          letter-spacing: normal;
        }
        .pretui-drawer-body {
          overflow-y: auto;
          color: var(--muted-foreground);
        }
        .pretui-drawer-footer {
          display: flex;
          justify-content: flex-end;
          gap: var(--boxel-sp-xs);
          border-top: 1px solid var(--border);
          padding-top: var(--boxel-sp-sm);
        }
        @media (prefers-reduced-motion: reduce) {
          .pretui-drawer[open] {
            transition: none;
          }
        }
      }
    </style>
  </template>
}
