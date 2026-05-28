// `@cardstack/surfaces` — headless component library and runtime
// for pattern-driven interactive semantics.
//
// The engine is renderer-agnostic: pure types + pure functions in
// `widget.ts`, `contracts.ts`, `rules.ts`, and `focus-ladder.ts`.
// Glimmer/Ember bindings live in `components/` and `modifiers/`.
//
// Two authoring dialects sit on the same engine:
//
//   Portable   Expanded markup; explicit @space, @coord, @schema;
//              local CSS + tokens. Lossless and copy-pasteable.
//
//   Adaptive   Concise, pattern-driven markup; runtime fills in
//              defaults (traversal, ARIA, responsive, Cue decals,
//              Place candidates) from contracts and rules.

export const SURFACES_DIST_VERSION = '@cardstack/surfaces@0.10.0';
export const SURFACES_DIST_BUILD = '__SURFACES_DIST_BUILD__';

export {
  isSurfaceTextEntryTarget,
  surfaceElementOwnsKeyboardEvent,
  surfaceTargetRetainsBrowserFocusAfterSelection,
  surfaceTargetOwnsKeyboardEvent,
  surfaceTargetOwnsPointerEvent,
} from './keyboard.ts';

// ─── widget shape ─────────────────────────────────────────────────

export type {
  Widget,
  Variants,
  Variants as SurfaceVariants,
  PreviewArgs,
  EditorArgs,
  EditAdvance,
  Surface,
  WidgetIntent,
  WidgetIntent as SurfaceWidgetIntent,
  PanePlacement,
} from './widget.ts';

// ─── surface contracts (interaction policy) ───────────────────────

export type {
  Intent,
  Intent as SurfaceIntent,
  Capability,
  Capability as SurfaceCapability,
  Contract,
  Contract as SurfaceContract,
  Policy,
  Policy as SurfacePolicy,
  InstanceContractOverrides,
  ContractNegotiationInput,
  ContractTable,
  LiftKind,
} from './contracts.ts';
export {
  FALLBACK_CONTRACT,
  BASE_CONTRACTS,
  registerContractTable,
  lookupBaseContract,
  negotiateContract,
  negotiateContract as negotiateSurfaceContract,
  negotiateForWidget,
} from './contracts.ts';

// ─── focus ladder (cross-host coordination) ───────────────────────

export { FocusLadder, createFocusLadder } from './focus-ladder.ts';
export type {
  LadderSurface,
  LadderRegistration,
  LadderNodeSnapshot,
  LadderAxis,
  LadderSelectOptions,
  Target,
  Target as SurfaceTarget,
  TargetMode,
  TargetMode as SurfaceTargetMode,
  TargetScope,
  TargetScope as SurfaceTargetScope,
} from './focus-ladder.ts';

// ─── surface runtime facade (Foci policy/store) ───────────────────

export { SurfaceRuntimeImpl, createSurfaceRuntime } from './surface-runtime.ts';
export type {
  SurfaceRuntime,
  SurfaceRuntimeNotificationScope,
  SurfaceRuntimeSubscriber,
  SurfaceRuntimeUpdateOptions,
  SurfaceRuntimeViewport,
} from './surface-runtime.ts';

// ─── foci store (pure semantic event reducer) ─────────────────────

export { FociStore, createFociStore } from './foci-store.ts';
export type {
  FociActivityRole,
  FociVisualTier,
  FociPointerPolicy,
  FociKeyboardPolicy,
  FociSelectionPolicy,
  FociEditPolicy,
  FociLiftPolicy,
  FociChromePolicy,
  FociAdornmentPresentation,
  FociAdornmentPolicy,
  FociDecalShape,
  FociMode,
  FociPreset,
  FociPresetAspect,
  FociCoordinateSpaceKind,
  FociSpaceMoveEffect,
  FociTraversalPolicy,
  FociTraversalModel,
  FociTraversalAxis,
  FociTraversalStopReason,
  FociCoordinateSpacePolicy,
  FociModeProjection,
  FociNodePolicy,
  FociGridCoordinate,
  FociNodeRegistration,
  FociNodeSnapshot,
  FociRangeSnapshot,
  FociSelectionSnapshot,
  FociActivityLayerSnapshot,
  FociInputSession,
  FociOverlaySession,
  FociDestinationSnapshot,
  FociTransferSnapshot,
  FociStoreSnapshot,
  FociDispatchResult,
  FociSelectOptions,
  FociTraversalOptions,
  FociTraversalStop,
  FociTraversalSet,
  FociProjectionAdornment,
  FociProjectionNode,
  FociProjectionDecal,
  FociProjection,
  FociSemanticEvent,
} from './foci-store.ts';

export { validateProjectionConformance } from './foci-projection-conformance.ts';
export type {
  FociProjectionAdapterNode,
  FociProjectionAdapterDecal,
  FociProjectionAdapterSnapshot,
  FociProjectionConformanceSeverity,
  FociProjectionConformanceIssue,
  FociProjectionNodeConformance,
  FociProjectionConformanceOptions,
  FociProjectionConformanceResult,
} from './foci-projection-conformance.ts';

// ─── surface layer manager ────────────────────────────────────────

export {
  SurfaceLayerManager,
  SurfaceLayerManager as LayerManager,
  SURFACE_LAYERS,
  LAYERS,
  collapseSurfaceLayerBoxes,
  clipSurfaceLayerRect,
} from './layer-manager.ts';
export type {
  SurfaceLayerRect,
  SurfaceLayerBox,
  SurfaceLayerBoxCollapseOptions,
  SurfaceLayerClipBounds,
  SurfaceLayerCornerRadii,
  SurfaceLayerTier,
  SurfaceLayerTier as LiftTier,
} from './layer-manager.ts';

// ─── modifiers ────────────────────────────────────────────────────

export { default as surfaceRoot } from './modifiers/root.ts';
export type {
  NavigationView,
  NavigationView as SurfaceNavigationView,
  RootOptions,
  RootOptions as SurfaceRootOptions,
} from './modifiers/root.ts';

export { default as surfaceNode } from './modifiers/node.ts';
export type {
  NodeOptions,
  NodeOptions as SurfaceNodeOptions,
} from './modifiers/node.ts';

export { default as surfaceScopeRelay } from './modifiers/scope-relay.ts';
export type { SurfaceScopeRelayOptions } from './modifiers/scope-relay.ts';
export {
  createSurfaceScopeRelay,
  isSurfaceScopeAttribute,
  mergeSurfaceScopeAttributes,
  stampSurfaceScope,
  surfaceScopeAttributesForElement,
  surfaceScopeAttributesForTree,
  SurfaceScopeContextName,
  SurfaceScopeRelay,
} from './scope-relay.ts';
export type {
  SurfaceScopeAttribute,
  SurfaceScopeAttributes,
} from './scope-relay.ts';

export { default as surfaceInlineEdit } from './modifiers/inline-edit.ts';
export { commitInlineEdits } from './modifiers/inline-edit.ts';
export { commitInlineEdits as commitSurfaceInlineEdits } from './modifiers/inline-edit.ts';
export type {
  InlineEditOptions,
  InlineEditOptions as SurfaceInlineEditOptions,
} from './modifiers/inline-edit.ts';

export { default as surfaceContinuousInput } from './modifiers/continuous-input.ts';
export type { ContinuousInputOptions } from './modifiers/continuous-input.ts';

export { default as surfaceCoordinateDebugger } from './modifiers/coordinate-debugger.ts';
export type {
  CoordinateDebugView,
  CoordinateDebugView as SurfaceCoordinateDebugView,
  CoordinateDebuggerOptions,
  CoordinateDebuggerOptions as SurfaceCoordinateDebuggerOptions,
} from './modifiers/coordinate-debugger.ts';

export { default as surfaceSelectionDecals } from './modifiers/selection-decals.ts';
export type { SurfaceSelectionDecalOptions } from './modifiers/selection-decals.ts';

export { default as surfaceDecalLayer } from './modifiers/decal-layer.ts';

export {
  default as surfaceGridBinding,
  cancelSurfaceGridInput,
  clearSurfaceGridSelection,
  commitSurfaceGridInput,
  releaseSurfaceGridDomFocus,
  restoreSurfaceGridSelection,
} from './modifiers/grid-binding.ts';
export type {
  SurfaceGridBindingOptions,
  SurfaceGridCancelOptions,
  SurfaceGridCommitOptions,
  SurfaceGridDomOptions,
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
export type {
  SurfaceDecalLayerClip,
  SurfaceDecalLayerOptions,
} from './modifiers/decal-layer.ts';

export { default as portal } from './modifiers/portal.ts';

export {
  ladderForSurfaceElement,
  parentSurfaceIdForElement,
  registerSurfaceDomNode,
  surfaceElementForId,
  surfaceElementsForIds,
  surfaceRuntimeForElement,
} from './dom-registry.ts';

export { default as multiUnit } from './modifiers/multi-unit.ts';
export type { MultiUnitOptions } from './modifiers/multi-unit.ts';

export { default as surfaceLiftBinding } from './modifiers/lift-binding.ts';
export type { LiftBindingArgs } from './modifiers/lift-binding.ts';

// ─── foundation surface components ────────────────────────────────

export {
  SurfaceComponent,
  SurfaceComponent as SurfaceComponentSurface,
  /** @deprecated Use `SurfaceComponent`. Removed in v3. */
  SurfaceComponent as AbstractFoundation,
  /** @deprecated Use `SurfaceComponentSurface`. Removed in v3. */
  SurfaceComponent as AbstractFoundationSurface,
  Environment,
  Environment as EnvironmentSurface,
  Layout as FoundationLayout,
  Canvas,
  Canvas as CanvasSurface,
  Scene,
  Scene as SceneSurface,
  Grid,
  Grid as GridSurface,
  Row,
  Row as RowSurface,
  Scroll,
  Scroll as ScrollSurface,
  Flow,
  Flow as FlowSurface,
  Frame,
  Frame as FrameSurface,
  Connection,
  Connection as ConnectionSurface,
  Pane,
  Pane as PaneSurface,
  Plane,
  Plane as PlaneSurface,
  Outline,
  Outline as OutlineSurface,
  Cell,
  Run,
  Run as RunSurface,
  Unit,
  Unit as UnitSurface,
  nextSurfaceId,
  surfaceFocusKey,
  surfaceFocusKeyFromPath,
  surfaceId,
  surfaceIdFromPath,
  LadderContextName,
  LadderContextName as SurfaceLadderContextName,
  SurfaceRuntimeContextName,
  ParentIdContextName,
  ParentIdContextName as ParentSurfaceIdContextName,
  ParentContextName,
  ParentContextName as ParentSurfaceContextName,
  DemoContextName,
  DemoContextName as SurfaceDemoContextName,
  ModeContextName,
  ModeContextName as SurfaceModeContextName,
  InspectContextName,
  InspectContextName as SurfaceInspectContextName,
  ChangeRouteContextName,
  ChangeRouteContextName as SurfaceChangeRouteContextName,
  CoordinateSpaceContextName,
  CoordinateSpaceContextName as SurfaceCoordinateSpaceContextName,
  PathContextName,
  PathContextName as SurfacePathContextName,
} from './components/surface-component.gts';
export type {
  SurfaceComponentSignature,
  /** @deprecated Use `SurfaceComponentSignature`. Removed in v3. */
  SurfaceComponentSignature as FoundationSignature,
  SurfaceComponentSignature as FoundationSurfaceSignature,
  EnvironmentSignature,
  EnvironmentSignature as EnvironmentSurfaceSignature,
  ChangeInput,
  ChangeInput as SurfaceChangeInput,
  ChangePreference,
  ChangePreference as SurfaceChangePreference,
  ChangeRoute,
  ChangeRoute as SurfaceChangeRoute,
  CoordinateSpaceContext,
  CoordinateSpaceContext as SurfaceCoordinateSpaceContext,
  CoordinateSpace,
  CoordinateSpace as SurfaceCoordinateSpace,
  DemoMode,
  DemoMode as SurfaceDemoMode,
  Identity,
  Identity as SurfaceIdentity,
  IdentityPart,
  IdentityPart as SurfaceIdentityPart,
  KeyboardMode,
  KeyboardMode as SurfaceKeyboardMode,
  LocalCoordinate,
  LocalCoordinate as SurfaceLocalCoordinate,
  Mode,
  Mode as SurfaceMode,
  Posture,
  Posture as SurfacePosture,
  Path,
  Path as SurfacePath,
  Role,
  Role as SurfaceRole,
  DirectiveScope,
  DirectiveScope as SurfaceDirectiveScope,
} from './components/surface-component.gts';

// ─── lift edges ───────────────────────────────────────────────────

export {
  LiftManager,
  LiftManager as SurfaceLiftManager,
  LiftContextName,
  LiftContextName as SurfaceLiftContextName,
  createLiftManager,
  createLiftManager as createSurfaceLiftManager,
} from './lift-edges.ts';
export type {
  LiftEdge,
  LiftEdge as SurfaceLiftEdge,
  LiftEdgeDeclaration,
  LiftEdgeDeclaration as SurfaceLiftEdgeDeclaration,
  LiftEdges,
  LiftEdges as SurfaceLiftEdges,
  LiftOpen,
  LiftOpen as SurfaceLiftOpen,
  LiftResolvedTarget,
  LiftResolvedTarget as SurfaceLiftResolvedTarget,
  LiftResolver,
  LiftResolver as SurfaceLiftResolver,
  LiftSource,
  LiftSource as SurfaceLiftSource,
  LiftTargetComponent,
  LiftTargetComponent as SurfaceLiftTargetComponent,
  LiftTargetContext,
  LiftTargetContext as SurfaceLiftTargetContext,
} from './lift-edges.ts';

// ─── cues / accessory components ──────────────────────────────────

export {
  CueDescription,
  CueLabel,
  CueStatus,
  Accessory,
  Accessory as SurfaceAccessory,
} from './components/accessory.gts';
export type {
  AccessoryAliasSignature,
  AccessoryAliasSignature as SurfaceAccessoryAliasSignature,
  AccessoryKind,
  AccessoryKind as SurfaceAccessoryKind,
  AccessoryPosition,
  AccessoryPosition as SurfaceAccessoryPosition,
  AccessorySignature,
  AccessorySignature as SurfaceAccessorySignature,
  AccessoryTone,
  AccessoryTone as SurfaceAccessoryTone,
} from './components/accessory.gts';

// ─── cell chrome deprecation aliases ──────────────────────────────

// Cell is the single public class. FieldCell remains as a one-release
// compatibility alias for realm cards that imported `FieldCell as Cell`.
/** @deprecated Use `Cell`. Removed in v3. */
export { Cell as FieldCell } from './components/surface-component.gts';
export type {
  CellSignature,
  CellSignature as FieldCellSignature,
  CellState,
  CellSurface,
  CellSurface as FieldCellSurface,
  CellValidationState,
} from './components/surface-component.gts';

export { default as Form } from './components/form.gts';
export type { FormSignature } from './components/form.gts';

export { default as FormField } from './components/form-field.gts';
export type { FormFieldSignature } from './components/form-field.gts';

export { FormFieldContextName } from './form-field-context.ts';
export type { FormFieldContext } from './form-field-context.ts';

export { default as FormSection } from './components/form-section.gts';
export type { FormSectionSignature } from './components/form-section.gts';

export { default as FormTab } from './components/form-tab.gts';
export type { FormTabSignature } from './components/form-tab.gts';

export { default as FormTabs } from './components/form-tabs.gts';
export type { FormTabsSignature } from './components/form-tabs.gts';

export { default as FormStep } from './components/form-step.gts';
export type { FormStepSignature } from './components/form-step.gts';

export { default as FormWizard } from './components/form-wizard.gts';
export type { FormWizardSignature } from './components/form-wizard.gts';

export { default as FormAlert } from './components/form-alert.gts';
export type {
  FormAlertSeverity,
  FormAlertSignature,
} from './components/form-alert.gts';

export { default as TextCell } from './components/text-cell.gts';
export type { TextCellSignature } from './components/text-cell.gts';

export { default as EmailCell } from './components/email-cell.gts';
export type { EmailCellSignature } from './components/email-cell.gts';

export { default as NumberCell } from './components/number-cell.gts';
export type { NumberCellSignature } from './components/number-cell.gts';

export { default as SwitchCell } from './components/switch-cell.gts';
export type { SwitchCellSignature } from './components/switch-cell.gts';

export {
  labelForFieldKey,
  readResolvedFormFieldValue,
  resolveFormFields,
  writeResolvedFormFieldValue,
} from './form-field-resolution.ts';
export type {
  FormMode,
  ResolvedFormField,
  ResolvedFormFieldInput,
  ResolvedFormFieldKind,
  ResolvedFormModel,
} from './form-field-resolution.ts';

// ─── lift shell + chevron ─────────────────────────────────────────

export { default as Lift } from './components/lift.gts';
export type { LiftSignature } from './components/lift.gts';

export { default as LiftChevron } from './components/lift-chevron.gts';
export type { LiftChevronSignature } from './components/lift-chevron.gts';

export { LiftState, createLiftState } from './lift-state.ts';
export type { LiftTarget, LiftStateOptions } from './lift-state.ts';

export {
  dampedRelativeScale,
  DEFAULT_RELATIVE_SCALE_MIN,
  DEFAULT_RELATIVE_SCALE_MAX,
} from './relative-scale.ts';

export { StableSizeGate } from './resize-stability.ts';
export type {
  StableSizeDecision,
  StableSizeDecisionReason,
  StableSizeGateOptions,
} from './resize-stability.ts';

// ─── boxel-layout ─────────────────────────────────────────────────
export { Layout } from '../packages/boxel-layout/index.ts';
export type { LayoutPreset, LayoutSignature } from '../packages/boxel-layout/index.ts';

// ─── boxel-grid (future) ──────────────────────────────────────────
// export { ... } from './boxel-grid/index.ts';

// ─── boxel-canvas (future) ────────────────────────────────────────
// export { ... } from './boxel-canvas/index.ts';
