// Public modifier barrel, matching the Boxel UI entrypoint pattern.

export { default as surfaceRoot } from './modifiers/root.ts';
export type { NavigationView, RootOptions } from './modifiers/root.ts';

export { default as surfaceNode } from './modifiers/node.ts';
export type { NodeOptions } from './modifiers/node.ts';

export { default as surfaceScopeRelay } from './modifiers/scope-relay.ts';
export type { SurfaceScopeRelayOptions } from './modifiers/scope-relay.ts';

export { default as surfaceInlineEdit } from './modifiers/inline-edit.ts';
export { commitInlineEdits } from './modifiers/inline-edit.ts';
export type { InlineEditOptions } from './modifiers/inline-edit.ts';

export { default as surfaceContinuousInput } from './modifiers/continuous-input.ts';
export type { ContinuousInputOptions } from './modifiers/continuous-input.ts';

export {
  default as surfaceGridBinding,
  cancelSurfaceGridInput,
  clearSurfaceGridSelection,
  commitSurfaceGridInput,
  releaseSurfaceGridDomFocus,
  restoreSurfaceGridSelection,
} from './modifiers/grid-binding.ts';
export type {
  SurfaceGridCancelOptions,
  SurfaceGridCommitOptions,
  SurfaceGridDomOptions,
  SurfaceGridBindingOptions,
  SurfaceGridSelection,
} from './modifiers/grid-binding.ts';

export {
  default as surfaceCanvasBinding,
  clearSurfaceCanvasSelection,
  releaseSurfaceCanvasDomFocus,
  restoreSurfaceCanvasSelection,
} from './modifiers/canvas-binding.ts';
export type {
  SurfaceCanvasAutoPan,
  SurfaceCanvasBindingOptions,
  SurfaceCanvasConnection,
  SurfaceCanvasDomOptions,
  SurfaceCanvasMarquee,
  SurfaceCanvasMove,
  SurfaceCanvasObjectKind,
  SurfaceCanvasPointerPhase,
  SurfaceCanvasReveal,
  SurfaceCanvasResize,
  SurfaceCanvasSelection,
  SurfaceCanvasSnapPosition,
} from './modifiers/canvas-binding.ts';

export {
  default as surfaceSceneBinding,
  clearSurfaceSceneSelection,
  releaseSurfaceSceneDomFocus,
  restoreSurfaceSceneSelection,
} from './modifiers/scene-binding.ts';
export type {
  SurfaceSceneAutoPan,
  SurfaceSceneBindingOptions,
  SurfaceSceneConnection,
  SurfaceSceneDomOptions,
  SurfaceSceneMarquee,
  SurfaceSceneMove,
  SurfaceSceneObjectKind,
  SurfaceScenePointerPhase,
  SurfaceSceneReveal,
  SurfaceSceneResize,
  SurfaceSceneSelection,
  SurfaceSceneSnapPosition,
} from './modifiers/scene-binding.ts';

export { default as surfaceCoordinateDebugger } from './modifiers/coordinate-debugger.ts';
export type {
  CoordinateDebugView,
  CoordinateDebuggerOptions,
} from './modifiers/coordinate-debugger.ts';

export { default as portal } from './modifiers/portal.ts';

export { default as multiUnit } from './modifiers/multi-unit.ts';
export type { MultiUnitOptions } from './modifiers/multi-unit.ts';

export { default as surfaceLiftBinding } from './modifiers/lift-binding.ts';
export type { LiftBindingArgs } from './modifiers/lift-binding.ts';
