// Public API for the standalone Popover package.
//
// This is a self-contained, remixable extraction of the boxel-surface
// `Lift` primitive. Its only npm dependency is `@floating-ui/dom`,
// which the Boxel host shims as a global virtual module — so a card
// that remixes this package works in any host-served realm with no
// install step.

export { default as Popover } from './components/popover.gts';
export type {
  PopoverSignature,
  PopoverKind,
  PopoverAnchoring,
  PopoverSize,
  PopoverBackdrop,
  PopoverElevation,
  PopoverKeyboardModel,
} from './components/popover.gts';

export { PopoverState, createPopoverState } from './utils/popover-state.ts';
export type {
  PopoverTarget,
  PopoverStateOptions,
  PopoverContract,
} from './utils/popover-state.ts';

export { default as surfacePopoverBinding } from './modifiers/popover-binding.ts';
export type { PopoverBindingArgs } from './modifiers/popover-binding.ts';
